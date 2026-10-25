import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/controller/cafe_controller.dart';
import 'package:klasik_grounds/services/api_service.dart';

void main() {
  for (final role in ['owner', 'cashier']) {
    test(
      '$role loads and refreshes recent sales without reloading the page',
      () async {
        var salesRequests = 0;
        var menuRequests = 0;
        final service = ApiService(
          client: MockClient((request) async {
            Object data = <Object>[];
            if (request.url.path == '/api/POS/transactions') {
              salesRequests++;
              data = [
                {
                  'sale_id': salesRequests,
                  'total_amount': '120.00',
                  'sale_date': '2026-10-18 10:30:00',
                  'item_count': '2',
                },
              ];
            } else if (request.url.path == '/api/Kiosk/products') {
              menuRequests++;
            }
            return http.Response(
              jsonEncode({'data': data}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final controller = CafeController(
          service: service,
          session: CafeSession(
            userId: 1,
            username: 'Test',
            role: role,
            sessionCookie: '',
          ),
        );
        addTearDown(controller.dispose);
        addTearDown(service.close);

        await controller.load();
        expect(controller.recentOrders.single.id, '1');
        expect(controller.recentOrdersErrorMessage, isNull);
        final loadingStates = <bool>[];
        controller.addListener(() => loadingStates.add(controller.loading));
        await controller.refreshRecentOrders();
        expect(controller.recentOrders.single.id, '2');
        expect(loadingStates, everyElement(isFalse));
        expect(menuRequests, 1);
        expect(salesRequests, 2);
      },
    );
  }

  for (final role in <String?>[
    null,
    'staff',
    'admin',
    'user',
    'loyal_customer',
  ]) {
    test('${role ?? 'guest'} does not request POS sales', () async {
      final service = ApiService(
        client: MockClient((request) async {
          expect(request.url.path, isNot('/api/POS/transactions'));
          return http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final controller = CafeController(
        service: service,
        session: role == null
            ? null
            : CafeSession(
                userId: 1,
                username: 'Test',
                role: role,
                sessionCookie: '',
              ),
      );
      addTearDown(controller.dispose);
      addTearDown(service.close);

      await controller.load();
      await controller.refreshRecentOrders();
      expect(controller.canViewRecentOrders, isFalse);
      expect(controller.recentOrders, isEmpty);
    });
  }

  test(
    'recent order failure leaves menu usable and refresh can recover',
    () async {
      var failSales = true;
      final service = ApiService(
        client: MockClient((request) async {
          if (request.url.path == '/api/POS/transactions') {
            return http.Response(
              jsonEncode(
                failSales
                    ? {'status': 'error', 'message': 'Authentication required.'}
                    : {
                        'data': [
                          {
                            'sale_id': 123,
                            'total_amount': 120,
                            'item_count': 1,
                          },
                        ],
                      },
              ),
              failSales ? 401 : 200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'data': request.url.path == '/api/Kiosk/products'
                  ? [
                      {
                        'product_id': 1,
                        'product_name': 'Latte',
                        'product_price': 120,
                      },
                    ]
                  : [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final controller = CafeController(
        service: service,
        session: const CafeSession(
          userId: 1,
          username: 'Test',
          role: 'cashier',
          sessionCookie: '',
        ),
      );
      addTearDown(controller.dispose);
      addTearDown(service.close);

      await controller.load();
      expect(controller.products.single.name, 'Latte');
      expect(controller.errorMessage, isNull);
      expect(
        controller.recentOrdersErrorMessage,
        contains('Authentication required'),
      );
      expect(controller.loading, isFalse);

      failSales = false;
      await controller.refreshRecentOrders();
      expect(controller.recentOrders.single.id, '123');
      expect(controller.recentOrdersErrorMessage, isNull);
    },
  );
}
