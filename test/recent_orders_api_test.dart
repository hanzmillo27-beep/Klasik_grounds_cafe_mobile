import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/services/api_service.dart';

void main() {
  ApiService serviceWithResponse(Object? body, {int statusCode = 200}) {
    final service = ApiService(
      sessionCookie: 'PHPSESSID=test-session',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/POS/transactions');
        expect(request.url.query, isEmpty);
        expect(request.headers['cookie'], 'PHPSESSID=test-session');
        expect(request.headers['accept'], 'application/json');
        return http.Response(
          jsonEncode(body),
          statusCode,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(service.close);
    return service;
  }

  test(
    'requests authenticated POS transactions and maps exact sale fields',
    () async {
      final service = serviceWithResponse({
        'data': [
          {
            'sale_id': '42',
            'user_id': '7',
            'customer_name': 'Guest',
            'total_amount': '240.50',
            'sale_date': '2026-10-18 12:30:00',
            'user_name': 'cashier',
            'item_count': '2',
          },
          {
            'sale_id': 41,
            'total_amount': 120,
            'sale_date': '2026-10-17 12:30:00',
            'item_count': 1,
          },
        ],
      });

      final orders = await service.fetchRecentOrders();

      expect(orders.map((order) => order.id), ['42', '41']);
      expect(orders.first.total, 240.50);
      expect(orders.first.itemCount, 2);
      expect(orders.first.createdAt, DateTime.utc(2026, 10, 18, 4, 30));
      expect(orders.first.status, 'completed');
      expect(orders.first.referenceCode, isEmpty);
      expect(orders.last.total, 120);
      expect(orders.last.itemCount, 1);
    },
  );

  test('does not reorder rows returned by the server', () async {
    final orders = await serviceWithResponse({
      'data': [
        {'sale_id': 2, 'sale_date': '2026-10-17 12:00:00'},
        {'sale_id': 9, 'sale_date': '2026-10-18 12:00:00'},
      ],
    }).fetchRecentOrders();

    expect(orders.map((order) => order.id), ['2', '9']);
  });

  test('an empty transactions list is a valid empty result', () async {
    expect(
      await serviceWithResponse({'data': []}).fetchRecentOrders(),
      isEmpty,
    );
  });

  for (final statusCode in [401, 403]) {
    test('surfaces authorization failure for HTTP $statusCode', () async {
      final service = serviceWithResponse({
        'status': 'error',
        'message': 'Access denied',
      }, statusCode: statusCode);

      await expectLater(
        service.fetchRecentOrders(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('authorization failed'),
              contains('/api/POS/transactions'),
            ),
          ),
        ),
      );
    });
  }

  test('HTTP 200 error payload is not an empty transaction history', () async {
    final service = serviceWithResponse({
      'status': 'error',
      'message': 'Cannot load transactions.',
      'data': [],
    });

    await expectLater(
      service.fetchRecentOrders(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Cannot load transactions.',
        ),
      ),
    );
  });

  for (final body in [
    null,
    'not JSON data',
    {},
    {'data': null},
    {'data': {}},
    [],
  ]) {
    test(
      'rejects malformed transactions response ${jsonEncode(body)}',
      () async {
        await expectLater(
          serviceWithResponse(body).fetchRecentOrders(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('invalid transactions list'),
            ),
          ),
        );
      },
    );
  }

  test('rejects malformed transaction rows', () async {
    for (final row in [
      null,
      'invalid',
      {},
      {'sale_id': {}},
    ]) {
      await expectLater(
        serviceWithResponse({
          'data': [row],
        }).fetchRecentOrders(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('invalid transaction'),
          ),
        ),
      );
    }
  });

  test('sale timestamps preserve explicit UTC or timezone offsets', () {
    for (final timestamp in [
      '2026-10-18T04:30:00Z',
      '2026-10-18T12:30:00+08:00',
      '2026-10-18T06:30:00+02:00',
      '2026-10-18 04:30:00+00',
      '2026-10-18 12:30:00+08',
    ]) {
      final order = CafeOrder.fromMap({'sale_date': timestamp});
      expect(order.createdAt, DateTime.utc(2026, 10, 18, 4, 30));
    }
  });

  test('missing or invalid sale dates remain unknown', () {
    for (final timestamp in [null, '', 'invalid', '2026-02-30 12:00:00']) {
      expect(CafeOrder.fromMap({'sale_date': timestamp}).createdAt, isNull);
    }
  });
}
