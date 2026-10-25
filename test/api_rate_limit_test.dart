import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/services/api_service.dart';
import 'package:klasik_grounds/services/rate_limiter.dart';

void main() {
  test(
    'sign-in allows five attempts, blocks before network, and expires',
    () async {
      var elapsed = Duration.zero;
      final limiter = RateLimiter(elapsed: () => elapsed);
      var requests = 0;
      ApiService service() {
        final api = ApiService(
          rateLimiter: limiter,
          client: MockClient((request) async {
            requests++;
            return http.Response('Login unavailable', 503);
          }),
        );
        addTearDown(api.close);
        return api;
      }

      final first = service();
      final second = service();
      for (var attempt = 0; attempt < 5; attempt++) {
        await expectLater(
          first.signIn(username: 'Guest', password: 'invalid'),
          throwsA(isA<StateError>()),
        );
      }
      expect(requests, 5);
      await expectLater(
        second.signIn(username: 'Different user', password: 'invalid'),
        throwsA(isA<RateLimitException>()),
      );
      expect(requests, 5);
      // A blocked attempt must not push the expiry later.
      elapsed = const Duration(seconds: 59);
      await expectLater(
        first.signIn(username: 'Guest', password: 'invalid'),
        throwsA(isA<RateLimitException>()),
      );
      elapsed = const Duration(minutes: 1);
      await expectLater(
        second.signIn(username: 'Guest', password: 'invalid'),
        throwsA(isA<StateError>()),
      );
      expect(requests, 6);
    },
  );

  test(
    'kiosk blocks rapid and concurrent retries without sending another POST',
    () async {
      var elapsed = Duration.zero;
      var posts = 0;
      final service = ApiService(
        rateLimiter: RateLimiter(elapsed: () => elapsed),
        client: MockClient((request) async {
          posts++;
          return http.Response(
            jsonEncode({'status': 'error', 'message': 'Rejected.'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(service.close);
      Future<String> submit() => service.createKioskOrder(
        customerName: 'Guest',
        customerUserId: null,
        items: [
          {'product_id': 1, 'quantity': 1},
        ],
      );

      final firstAttempt = expectLater(submit(), throwsA(isA<StateError>()));
      await expectLater(submit(), throwsA(isA<RateLimitException>()));
      await firstAttempt;
      expect(posts, 1);
      elapsed = const Duration(seconds: 3);
      await expectLater(submit(), throwsA(isA<StateError>()));
      expect(posts, 2);
    },
  );

  test('invalid kiosk input does not consume the order budget', () async {
    var posts = 0;
    final service = ApiService(
      rateLimiter: RateLimiter(),
      client: MockClient((request) async {
        posts++;
        return http.Response(
          jsonEncode({'status': 'success', 'reference_code': 'KG-1234ABCD'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(service.close);
    for (var attempt = 0; attempt < 3; attempt++) {
      await expectLater(
        service.createKioskOrder(
          customerName: '',
          customerUserId: null,
          items: [
            {'product_id': 1, 'quantity': 1},
          ],
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        service.createKioskOrder(
          customerName: 'Guest',
          customerUserId: null,
          items: [],
        ),
        throwsA(isA<StateError>()),
      );
    }
    expect(
      await service.createKioskOrder(
        customerName: 'Guest',
        customerUserId: null,
        items: [
          {'product_id': 1, 'quantity': 1},
        ],
      ),
      'KG-1234ABCD',
    );
    expect(posts, 1);
  });

  test(
    'default service instances share the running app sign-in budget',
    () async {
      var requests = 0;
      ApiService service() {
        final api = ApiService(
          client: MockClient((request) async {
            requests++;
            return http.Response('', 503);
          }),
        );
        addTearDown(api.close);
        return api;
      }

      for (var attempt = 0; attempt < 5; attempt++) {
        await expectLater(
          service().signIn(username: 'Guest', password: 'invalid'),
          throwsA(isA<StateError>()),
        );
      }
      await expectLater(
        service().signIn(username: 'Guest', password: 'invalid'),
        throwsA(isA<RateLimitException>()),
      );
      expect(requests, 5);
    },
  );
}
