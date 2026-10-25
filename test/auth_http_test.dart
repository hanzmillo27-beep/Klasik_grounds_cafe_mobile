import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:klasik_grounds/services/api_service.dart';
import 'package:klasik_grounds/services/rate_limiter.dart';

void main() {
  test(
    'native HTTP preserves login fields and the rotated PHP session',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final cookies = <String, String?>{};
      Map<String, String>? submitted;
      server.listen((request) async {
        final path = request.uri.path;
        paths.add(path);
        cookies[path] = request.headers.value(HttpHeaders.cookieHeader);
        if (path == '/Auth') {
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'unrelated=first; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/',
          );
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'PHPSESSID=initial-session; Path=/; HttpOnly',
          );
          request.response.write('<form method="post"></form>');
        } else if (path == '/Auth/login') {
          submitted = Uri.splitQueryString(
            await utf8.decoder.bind(request).join(),
          );
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            '/Dashboard',
          );
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'unrelated=next; Path=/',
          );
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'PHPSESSID=rotated-session; Path=/; HttpOnly',
          );
        } else if (path == '/api/Kiosk/products') {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"data":[]}');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      final service = ApiService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        rateLimiter: RateLimiter(),
      );
      addTearDown(service.close);

      final session = await service.signIn(
        username: '  café.owner  ',
        password: ' space +p&?=✓ ',
      );
      expect(session.role, 'owner');
      expect(session.username, 'café.owner');
      expect(session.sessionCookie, 'PHPSESSID=rotated-session');
      expect(submitted, {
        'username': 'café.owner',
        'password': ' space +p&?=✓ ',
      });
      expect(cookies['/Auth/login'], 'PHPSESSID=initial-session');
      expect(await service.fetchProducts(), isEmpty);
      expect(cookies['/api/Kiosk/products'], 'PHPSESSID=rotated-session');
      expect(paths, ['/Auth', '/Auth/login', '/api/Kiosk/products']);
    },
  );
}
