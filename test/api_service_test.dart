import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/services/api_service.dart';
import 'package:klasik_grounds/services/rate_limiter.dart';

void main() {
  Future<String> submit(Object? response) async {
    final service = ApiService(
      rateLimiter: RateLimiter(),
      client: MockClient((request) async {
        expect(request.url.path, '/api/Kiosk/submit');
        expect(request.method, 'POST');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data; boundary='),
        );
        expect(request.body, contains('name="customer_name"\r\n\r\nGuest'));
        expect(
          request.body,
          contains(
            'name="items"\r\n\r\n'
            '[{"product_id":1,"quantity":1}]',
          ),
        );
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(service.close);
    return service.createKioskOrder(
      customerName: 'Guest',
      customerUserId: null,
      items: [
        {'product_id': 1, 'quantity': 1},
      ],
    );
  }

  test(
    'matches the cafe kiosk success response and multipart request',
    () async {
      expect(
        await submit({
          'status': 'success',
          'message': 'Order submitted. Please pay at the cashier.',
          'reference_code': 'KG-F329F30B',
          'total_amount': 120,
        }),
        'KG-F329F30B',
      );
    },
  );

  test('shows server rejection message even with HTTP 200', () async {
    await expectLater(
      submit({'status': 'error', 'message': 'Your cart is empty.'}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Your cart is empty.',
        ),
      ),
    );
  });

  test('keeps reference outside the data envelope', () async {
    expect(
      await submit({
        'status': 'success',
        'reference_code': 'KG-F329F30B',
        'data': null,
      }),
      'KG-F329F30B',
    );
  });

  test(
    'does not substitute a numeric order ID for a cashier reference',
    () async {
      await expectLater(
        submit({
          'status': 'success',
          'data': {
            'order': {'order_id': 42},
          },
        }),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'requires server success even if a reference field is present',
    () async {
      await expectLater(
        submit({'reference_code': 'KG-F329F30B'}),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('does not treat rejection as an order receipt', () async {
    await expectLater(
      submit({'success': false, 'message': 'Out of stock', 'order_id': 42}),
      throwsA(isA<StateError>()),
    );
  });

  test('missing reference warns against resubmission', () async {
    await expectLater(
      submit({'status': 'success'}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('duplicate order'),
        ),
      ),
    );
  });
}
