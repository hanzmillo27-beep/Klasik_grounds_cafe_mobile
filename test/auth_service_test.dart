import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/services/api_service.dart';
import 'package:klasik_grounds/services/rate_limiter.dart';

void main() {
  const origin = 'https://cafe.example';
  const initialCookie = 'PHPSESSID=initial-session';
  const rotatedCookie = 'PHPSESSID=rotated-session';
  const unconfirmedMessage =
      'The server did not confirm your account access. '
      'Please try again or check your account role.';

  ApiService serviceUsing(
    Future<http.Response> Function(http.Request) respond,
  ) {
    final service = ApiService(
      baseUrl: origin,
      rateLimiter: RateLimiter(),
      client: MockClient(respond),
    );
    addTearDown(service.close);
    return service;
  }

  http.Response initialLoginPage() => http.Response(
    '<html><body><form>Sign in</form></body></html>',
    200,
    headers: {
      'content-type': 'text/html',
      'set-cookie': '$initialCookie; Path=/; HttpOnly',
    },
  );

  String alertPage(String message) =>
      '<!doctype html><html><head><title>Klasik Grounds</title></head>'
      '<body><h1>Welcome to the cafe</h1>'
      '<div class="alert alert-danger kg-alert" role="alert">$message</div>'
      '<footer>All day, your way</footer></body></html>';

  for (final entry in {
    '/Dashboard': 'owner',
    '/Products': 'staff',
    '/Users': 'admin',
    '/POS': 'cashier',
    '/Loyalty': 'loyal_customer',
    '/Kiosk': 'user',
  }.entries) {
    test('accepts confirmed ${entry.value} account redirect', () async {
      final requests = <http.Request>[];
      final service = serviceUsing((request) async {
        requests.add(request);
        if (request.method == 'GET') return initialLoginPage();
        expect(request.url.path, '/Auth/login');
        expect(request.followRedirects, isFalse);
        expect(request.headers['cookie'], initialCookie);
        return http.Response('', 302, headers: {'location': entry.key});
      });

      final session = await service.signIn(
        username: ' member ',
        password: 'password',
      );

      expect(session.username, 'member');
      expect(session.role, entry.value);
      expect(session.sessionCookie, initialCookie);
      expect(requests.map((request) => request.method), ['GET', 'POST']);
      expect(requests.first.url.toString(), '$origin/Auth');
    });
  }

  test('encodes exact credentials and forwards only the rotated PHP session', () async {
    final requests = <http.Request>[];
    const password = ' pa+ss&word=secret ';
    final service = serviceUsing((request) async {
      requests.add(request);
      switch (request.url.path) {
        case '/Auth':
          expect(request.method, 'GET');
          return http.Response(
            '',
            200,
            headers: {
              'content-type': 'text/html',
              'set-cookie':
                  'analytics=quiet; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/, '
                  '$initialCookie; Path=/; HttpOnly',
            },
          );
        case '/Auth/login':
          expect(request.method, 'POST');
          expect(request.followRedirects, isFalse);
          expect(request.headers['cookie'], initialCookie);
          expect(
            request.headers['content-type'],
            startsWith('application/x-www-form-urlencoded'),
          );
          expect(Uri.splitQueryString(request.body), {
            'username': 'member+name',
            'password': password,
          });
          return http.Response(
            '',
            302,
            headers: {
              'location': '$origin/POS',
              'set-cookie':
                  'feature=on; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/, '
                  '$rotatedCookie; Path=/; Secure; HttpOnly',
            },
          );
        case '/api/Kiosk/products':
          expect(request.method, 'GET');
          expect(request.headers['cookie'], rotatedCookie);
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        default:
          fail('Unexpected request: ${request.method} ${request.url.path}');
      }
    });

    final session = await service.signIn(
      username: '  member+name  ',
      password: password,
    );
    expect(session.role, 'cashier');
    expect(session.sessionCookie, rotatedCookie);
    expect(service.sessionCookie, rotatedCookie);
    expect(await service.fetchProducts(), isEmpty);
    expect(requests, hasLength(3));
  });

  test(
    'unrelated response cookies do not overwrite an existing PHP session',
    () async {
      final service = serviceUsing((request) async {
        if (request.method == 'GET') {
          return http.Response(
            '',
            200,
            headers: {
              'set-cookie':
                  'theme=dark; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
            },
          );
        }
        expect(request.headers['cookie'], initialCookie);
        return http.Response('', 302, headers: {'location': '/Kiosk'});
      });
      service.sessionCookie = initialCookie;

      final session = await service.signIn(
        username: 'member',
        password: 'password',
      );

      expect(session.sessionCookie, initialCookie);
      expect(service.sessionCookie, initialCookie);
    },
  );

  test(
    'failed redirect reads the flash once with the latest session cookie',
    () async {
      final requests = <http.Request>[];
      var loginPageReads = 0;
      const message = "Your account's role & access is unavailable.";
      final service = serviceUsing((request) async {
        requests.add(request);
        expect(request.url.origin, origin);
        if (request.method == 'POST') {
          expect(request.url.path, '/Auth/login');
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {
              'location': '$origin/Auth',
              'set-cookie':
                  'theme=dark; Path=/, $rotatedCookie; Path=/; HttpOnly',
            },
          );
        }
        expect(request.url.path, '/Auth');
        expect(request.followRedirects, isFalse);
        loginPageReads++;
        if (loginPageReads == 1) return initialLoginPage();
        expect(request.headers['cookie'], rotatedCookie);
        return http.Response(
          alertPage(
            'Your account&#039;s <strong>role &amp; access</strong> is unavailable.',
          ),
          200,
          headers: {'content-type': 'text/html'},
        );
      });

      await expectLater(
        service.signIn(username: 'member', password: 'wrong'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            message,
          ),
        ),
      );
      expect(requests.map((request) => request.method), ['GET', 'POST', 'GET']);
      expect(loginPageReads, 2);
      expect(service.sessionCookie, rotatedCookie);
    },
  );

  test('failed redirect without a flash reports unconfirmed access', () async {
    final requests = <http.Request>[];
    final service = serviceUsing((request) async {
      requests.add(request);
      if (request.method == 'GET') return initialLoginPage();
      return http.Response('', 302, headers: {'location': '/Auth'});
    });

    await expectLater(
      service.signIn(username: 'member', password: 'wrong'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          unconfirmedMessage,
        ),
      ),
    );
    expect(requests.map((request) => request.method), ['GET', 'POST', 'GET']);
  });

  for (final limitedStep in ['GET', 'POST']) {
    test(
      'HTTP 429 at $limitedStep honors Retry-After and the server alert',
      () async {
        final requests = <http.Request>[];
        const message = 'Please wait before signing in again.';
        final service = serviceUsing((request) async {
          requests.add(request);
          if (request.method == 'GET' && limitedStep == 'POST') {
            return initialLoginPage();
          }
          return http.Response(
            alertPage(message),
            429,
            headers: {'content-type': 'text/html', 'retry-after': '42'},
          );
        });

        await expectLater(
          service.signIn(username: 'member', password: 'password'),
          throwsA(
            isA<RateLimitException>()
                .having(
                  (error) => error.retryAfter,
                  'retryAfter',
                  const Duration(seconds: 42),
                )
                .having((error) => error.message, 'message', message),
          ),
        );
        expect(requests.length, limitedStep == 'GET' ? 1 : 2);
      },
    );
  }

  test('HTTP 503 shows the alert without unrelated page content', () async {
    final requests = <http.Request>[];
    const message = 'Sign-in is temporarily unavailable. Please try again.';
    final service = serviceUsing((request) async {
      requests.add(request);
      if (request.method == 'GET') return initialLoginPage();
      return http.Response(
        alertPage(message),
        503,
        headers: {'content-type': 'text/html'},
      );
    });

    await expectLater(
      service.signIn(username: 'member', password: 'password'),
      throwsA(
        isA<StateError>().having((error) => error.message, 'message', message),
      ),
    );
    expect(requests, hasLength(2));
  });

  for (final redirect in [
    'https://other.example/POS',
    '//other.example/POS',
    'https://other.example/Auth',
  ]) {
    test(
      'rejects external redirect $redirect without forwarding cookies',
      () async {
        final requests = <http.Request>[];
        final service = serviceUsing((request) async {
          requests.add(request);
          if (request.method == 'GET') return initialLoginPage();
          return http.Response('', 302, headers: {'location': redirect});
        });

        await expectLater(
          service.signIn(username: 'member', password: 'password'),
          throwsA(isA<StateError>()),
        );
        expect(requests.map((request) => request.method), ['GET', 'POST']);
        expect(
          requests.every((request) => request.url.origin == origin),
          isTrue,
        );
      },
    );
  }

  test('a response with no redirect never confirms a session', () async {
    final requests = <http.Request>[];
    final service = serviceUsing((request) async {
      requests.add(request);
      if (request.method == 'GET') return initialLoginPage();
      return http.Response('', 302);
    });

    await expectLater(
      service.signIn(username: 'member', password: 'password'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          isNotEmpty,
        ),
      ),
    );
    expect(requests, hasLength(2));
  });
}
