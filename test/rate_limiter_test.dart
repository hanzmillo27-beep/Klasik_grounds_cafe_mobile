import 'package:flutter_test/flutter_test.dart';
import 'package:klasik_grounds/services/rate_limiter.dart';

void main() {
  group('RateLimiter', () {
    late Duration elapsed;
    late RateLimiter limiter;

    setUp(() {
      elapsed = Duration.zero;
      limiter = RateLimiter(elapsed: () => elapsed);
    });

    test('permits the configured budget again at the exact expiry', () {
      void check() => limiter.check(
        'orders',
        limit: 2,
        window: const Duration(seconds: 10),
      );

      check();
      check();
      expect(check, throwsA(_limited('orders', const Duration(seconds: 10))));

      elapsed = const Duration(seconds: 10) - const Duration(microseconds: 1);
      expect(
        check,
        throwsA(_limited('orders', const Duration(microseconds: 1))),
      );

      elapsed = const Duration(seconds: 10);
      expect(check, returnsNormally);
      expect(check, returnsNormally);
      expect(check, throwsA(_limited('orders', const Duration(seconds: 10))));
    });

    test('expires staggered attempts individually in a rolling window', () {
      void check() => limiter.check(
        'orders',
        limit: 2,
        window: const Duration(seconds: 10),
      );

      check();
      elapsed = const Duration(seconds: 4);
      check();
      elapsed = const Duration(seconds: 9);
      expect(check, throwsA(_limited('orders', const Duration(seconds: 1))));

      elapsed = const Duration(seconds: 10);
      expect(check, returnsNormally);
      expect(check, throwsA(_limited('orders', const Duration(seconds: 4))));

      elapsed = const Duration(seconds: 14);
      expect(check, returnsNormally);
      expect(check, throwsA(_limited('orders', const Duration(seconds: 6))));
    });

    test('blocked calls neither extend the wait nor consume another slot', () {
      void check() => limiter.check(
        'logins',
        limit: 1,
        window: const Duration(seconds: 10),
      );

      check();
      for (final seconds in [2, 5, 9]) {
        elapsed = Duration(seconds: seconds);
        expect(
          check,
          throwsA(_limited('logins', Duration(seconds: 10 - seconds))),
        );
      }

      elapsed = const Duration(seconds: 10);
      expect(check, returnsNormally);
      expect(check, throwsA(_limited('logins', const Duration(seconds: 10))));
      elapsed = const Duration(seconds: 20);
      expect(check, returnsNormally);
    });

    test('keeps independent budgets for different action keys', () {
      void check(String action) =>
          limiter.check(action, limit: 1, window: const Duration(seconds: 10));

      check('orders');
      elapsed = const Duration(seconds: 3);
      expect(() => check('logins'), returnsNormally);
      expect(
        () => check('orders'),
        throwsA(_limited('orders', const Duration(seconds: 7))),
      );

      elapsed = const Duration(seconds: 10);
      expect(() => check('orders'), returnsNormally);
      expect(
        () => check('logins'),
        throwsA(_limited('logins', const Duration(seconds: 3))),
      );
    });

    test('requires a positive limit and window without consuming a slot', () {
      for (final limit in [0, -1]) {
        expect(
          () => limiter.check(
            'orders',
            limit: limit,
            window: const Duration(seconds: 10),
          ),
          throwsArgumentError,
        );
      }
      for (final window in [Duration.zero, const Duration(microseconds: -1)]) {
        expect(
          () => limiter.check('orders', limit: 1, window: window),
          throwsArgumentError,
        );
      }

      expect(
        () => limiter.check(
          'orders',
          limit: 1,
          window: const Duration(seconds: 10),
        ),
        returnsNormally,
      );
    });
  });

  group('RateLimitException', () {
    test('rounds remaining seconds upward including subsecond waits', () {
      final cases = {
        const Duration(microseconds: 1): 1,
        const Duration(microseconds: 999999): 1,
        const Duration(seconds: 1): 1,
        const Duration(microseconds: 1000001): 2,
        const Duration(microseconds: 1999999): 2,
        const Duration(seconds: 2): 2,
      };

      for (final entry in cases.entries) {
        final error = RateLimitException(
          action: 'orders',
          retryAfter: entry.key,
        );
        expect(error.retryAfterSeconds, entry.value, reason: '${entry.key}');
      }
    });

    test('includes the action and singular or plural wait in its message', () {
      const shortWait = RateLimitException(
        action: 'login attempts',
        retryAfter: Duration(milliseconds: 50),
      );
      const longerWait = RateLimitException(
        action: 'order submissions',
        retryAfter: Duration(milliseconds: 1001),
      );

      expect(
        shortWait.message,
        'Too many login attempts. Try again in 1 second.',
      );
      expect(
        longerWait.message,
        'Too many order submissions. Try again in 2 seconds.',
      );
      expect(shortWait.toString(), shortWait.message);
      expect(longerWait.toString(), longerWait.message);
    });
  });
}

Matcher _limited(String action, Duration retryAfter) =>
    isA<RateLimitException>()
        .having((error) => error.action, 'action', action)
        .having((error) => error.retryAfter, 'retryAfter', retryAfter);
