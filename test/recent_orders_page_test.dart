import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/home_page/home_page.dart';
import 'package:klasik_grounds/services/api_service.dart';

void main() {
  testWidgets('recent orders show sales, refresh errors, and empty results', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var salesRequests = 0;

    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: HomePage(
              session: const CafeSession(
                userId: 4,
                username: 'Cashier',
                role: 'cashier',
                sessionCookie: 'PHPSESSID=test',
              ),
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Order #123'));
        expect(find.text('2 line items · Date unavailable'), findsOneWidget);
        expect(find.text('COMPLETED'), findsOneWidget);

        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Could not load recent orders.'),
          findsOneWidget,
        );
        expect(find.text('Order #123'), findsOneWidget);
        expect(find.text('No completed orders yet.'), findsNothing);

        await tester.ensureVisible(find.text('Refresh'));
        await tester.tap(find.text('Refresh'));
        await tester.pumpAndSettle();
        expect(find.text('No completed orders yet.'), findsOneWidget);
        expect(
          find.textContaining('Could not load recent orders.'),
          findsNothing,
        );
        expect(find.text('Order #123'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        Object data = {'data': []};
        var status = 200;
        if (request.url.path == '/api/POS/transactions') {
          salesRequests++;
          if (salesRequests == 1) {
            data = {
              'data': [
                {'sale_id': 123, 'total_amount': '240.00', 'item_count': '2'},
              ],
            };
          } else if (salesRequests == 2) {
            status = 403;
            data = {'status': 'error', 'message': 'Permission denied.'};
          }
        }
        return http.Response(
          jsonEncode(data),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
}
