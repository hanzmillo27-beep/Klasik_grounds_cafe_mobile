import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/services/api_service.dart';

void main() {
  Map<String, dynamic> receipt() => {
    'reward_code': 'GC-1234ABCD',
    'product_id': 2,
    'product_name': 'Cheesecake',
    'points': 17,
    'points_spent': 10,
  };

  ApiService serviceWith(Future<http.Response> Function(http.Request) respond) {
    final service = ApiService(
      client: MockClient(respond),
      sessionCookie: 'PHPSESSID=member-session',
    );
    addTearDown(service.close);
    return service;
  }

  http.Response jsonResponse(Object? body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );

  test(
    'redeems the selected product using the authenticated item endpoint',
    () async {
      final service = serviceWith((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/Loyalty/redeemItem');
        expect(request.headers['cookie'], 'PHPSESSID=member-session');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), {'product_id': 2});
        return jsonResponse({'status': 'success', 'data': receipt()});
      });

      final result = await service.redeemLoyalty(productId: '2');

      expect(result.rewardCode, 'GC-1234ABCD');
      expect(result.productId, '2');
      expect(result.productName, 'Cheesecake');
      expect(result.points, 17);
      expect(result.pointsSpent, 10);
    },
  );

  test('rejects invalid product IDs without sending a request', () async {
    var requests = 0;
    final service = serviceWith((_) async {
      requests++;
      return jsonResponse({});
    });

    for (final id in ['', 'latte', '0', '-3', '2.5']) {
      await expectLater(
        service.redeemLoyalty(productId: id),
        throwsA(isA<StateError>()),
      );
    }
    expect(requests, 0);
  });

  test('surfaces a business rejection even when HTTP status is 200', () async {
    final service = serviceWith(
      (_) async => jsonResponse({
        'status': 'error',
        'message': 'You need 10 points to redeem an item.',
      }),
    );

    await expectLater(
      service.redeemLoyalty(productId: '2'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'You need 10 points to redeem an item.',
        ),
      ),
    );
  });

  test('does not accept a receipt without explicit server success', () async {
    final service = serviceWith((_) async => jsonResponse({'data': receipt()}));

    await expectLater(
      service.redeemLoyalty(productId: '2'),
      throwsA(isA<StateError>()),
    );
  });

  final invalidReceiptChanges = <String, Map<String, dynamic>>{
    'missing voucher': {'reward_code': null},
    'blank voucher': {'reward_code': '  '},
    'missing chosen item': {'product_name': null},
    'different chosen item': {'product_id': 1},
    'missing balance': {'points': null},
    'negative balance': {'points': -1},
    'fractional balance': {'points': 1.5},
    'different points cost': {'points_spent': 20},
  };
  for (final entry in invalidReceiptChanges.entries) {
    test('rejects ${entry.key} and warns before another redemption', () async {
      final service = serviceWith(
        (_) async => jsonResponse({
          'status': 'success',
          'data': {...receipt(), ...entry.value},
        }),
      );

      await expectLater(
        service.redeemLoyalty(productId: '2'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Check with the cafe before redeeming again'),
          ),
        ),
      );
    });
  }

  test('a rejected HTTP response never becomes a redemption receipt', () async {
    final service = serviceWith(
      (_) async => jsonResponse({
        'status': 'error',
        'message': 'This item is no longer available.',
      }, status: 400),
    );

    await expectLater(
      service.redeemLoyalty(productId: '2'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'This item is no longer available.',
        ),
      ),
    );
  });

  test(
    'an older server does not fall back to spending points on generic coffee',
    () async {
      final paths = <String>[];
      final service = serviceWith((request) async {
        paths.add(request.url.path);
        return jsonResponse({'message': 'Route not found.'}, status: 404);
      });

      await expectLater(
        service.redeemLoyalty(productId: '2'),
        throwsA(isA<StateError>()),
      );
      expect(paths, ['/api/Loyalty/redeemItem']);
    },
  );

  test('a recipe stock shortage makes an item unavailable for redemption', () {
    final product = CafeProduct.fromMap({
      'product_id': 2,
      'product_name': 'Cheesecake',
      'is_available': true,
      'can_order': false,
    });

    expect(product.isAvailable, isFalse);
  });
}
