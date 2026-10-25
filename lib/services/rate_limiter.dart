import 'dart:collection';

class RateLimitException implements Exception {
  const RateLimitException({
    required this.action,
    required this.retryAfter,
    this.serverMessage,
  });

  final String action;
  final Duration retryAfter;
  final String? serverMessage;

  int get retryAfterSeconds =>
      (retryAfter.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
      Duration.microsecondsPerSecond;

  String get message =>
      serverMessage ??
      'Too many $action. Try again in $retryAfterSeconds '
          '${retryAfterSeconds == 1 ? 'second' : 'seconds'}.';

  @override
  String toString() => message;
}

/// An in-memory rolling limit, using elapsed time rather than the device clock.
class RateLimiter {
  RateLimiter({Duration Function()? elapsed}) : _elapsed = elapsed ?? _clock();

  final Duration Function() _elapsed;
  final _attempts = <String, Queue<Duration>>{};

  static Duration Function() _clock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  void check(String action, {required int limit, required Duration window}) {
    if (limit < 1 || window <= Duration.zero) {
      throw ArgumentError('The request limit and window must be positive.');
    }
    final now = _elapsed();
    final attempts = _attempts.putIfAbsent(action, Queue<Duration>.new);
    while (attempts.isNotEmpty && attempts.first <= now - window) {
      attempts.removeFirst();
    }
    if (attempts.length >= limit) {
      throw RateLimitException(
        action: action,
        retryAfter: attempts.first + window - now,
      );
    }
    attempts.addLast(now);
  }
}
