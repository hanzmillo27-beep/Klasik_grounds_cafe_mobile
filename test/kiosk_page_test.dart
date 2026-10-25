import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/home_page/home_page.dart';

void main() {
  testWidgets('mobile kiosk shows empty cart and keeps confirmed receipt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var submissions = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(home: HomePage(session: null, onExit: () {})),
        );
        await tester.pumpAndSettle();

        expect(find.text('Your cart is empty'), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
        // Find the checkout button by its icon, allowing the displayed total.
        final checkout = find.ancestor(
          of: find.byIcon(Icons.arrow_forward_rounded),
          matching: find.byType(ElevatedButton),
        );
        expect(tester.widget<ElevatedButton>(checkout).onPressed, isNull);

        await tester.tap(find.byTooltip('Add Latte'));
        await tester.pumpAndSettle();
        expect(find.text('Your cart is empty'), findsNothing);
        await tester.enterText(find.byType(TextField), 'Guest');
        await tester.tap(checkout);
        await tester.pumpAndSettle();

        expect(submissions, 1);
        expect(find.text('Order submitted'), findsOneWidget);
        expect(find.text('KG-42'), findsOneWidget);
        expect(
          find.text('Your order is not paid yet. Pay at the cashier.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Start new order'));
        await tester.pumpAndSettle();
        expect(find.text('Your cart is empty'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      () => MockClient((request) async {
        final Object response;
        if (request.method == 'POST') {
          submissions++;
          response = {
            'status': 'success',
            'reference_code': 'KG-42',
            'total_amount': 120,
          };
        } else {
          response = {
            'data': [
              {'product_id': 1, 'product_name': 'Latte', 'product_price': 120},
            ],
          };
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
}
