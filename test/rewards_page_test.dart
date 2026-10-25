import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/home_page/home_page.dart';
import 'package:klasik_grounds/services/api_service.dart';

http.Response jsonResponse(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response rewardResponse({int points = 15}) => jsonResponse({
  'status': 'success',
  'data': {
    'reward_code': 'GC-CHOICE12',
    'product_id': 2,
    'product_name': 'Croissant',
    'points': points,
    'points_spent': 10,
  },
});

Future<void> withRewards(
  WidgetTester tester, {
  required int points,
  required Future<http.Response> Function(http.Request) redeem,
  required Future<void> Function() interact,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await http.runWithClient(
    () async {
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            session: const CafeSession(
              userId: 9,
              username: 'Member',
              role: 'loyal_customer',
              sessionCookie: 'PHPSESSID=member',
            ),
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rewards'));
      await tester.pumpAndSettle();
      await interact();
      expect(tester.takeException(), isNull);
    },
    () => MockClient((request) async {
      if (request.method == 'POST') return redeem(request);
      if (request.url.path == '/api/Loyalty/summary') {
        return jsonResponse({
          'status': 'success',
          'data': {'points': points},
        });
      }
      return jsonResponse({
        'data': [
          {
            'product_id': 1,
            'product_name': 'Latte',
            'product_price': 120,
            'category': 'Coffee',
            'is_available': true,
          },
          {
            'product_id': 2,
            'product_name': 'Croissant',
            'product_price': 90,
            'category': 'Pastry',
            'is_available': true,
          },
          {
            'product_id': 3,
            'product_name': 'Unavailable cake',
            'product_price': 180,
            'is_available': false,
          },
        ],
      });
    }),
  );
}

void main() {
  testWidgets('customer chooses an item and keeps the confirmed reward code', (
    tester,
  ) async {
    var submissions = 0;
    await withRewards(
      tester,
      points: 25,
      redeem: (request) async {
        submissions++;
        expect(request.url.path, '/api/Loyalty/redeemItem');
        expect(jsonDecode(request.body), {'product_id': 2});
        return rewardResponse();
      },
      interact: () async {
        expect(find.textContaining('2 free items available'), findsOneWidget);
        await tester.tap(find.text('Redeem'));
        await tester.pumpAndSettle();
        expect(find.text('Unavailable cake'), findsNothing);
        final confirm = find.widgetWithText(
          ElevatedButton,
          'Redeem for 10 points',
        );
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
        await tester.tap(find.text('Croissant'));
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        expect(submissions, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.textContaining('1 free item available'), findsOneWidget);
        await tester.ensureVisible(find.text('GC-CHOICE12'));
        expect(find.text('Croissant'), findsOneWidget);
        expect(find.text('GC-CHOICE12'), findsOneWidget);
        expect(find.textContaining('10 points redeemed.'), findsOneWidget);
        expect(find.text('15'), findsWidgets);

        await tester.tap(find.text('Kiosk'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rewards'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('GC-CHOICE12'));
        expect(find.text('GC-CHOICE12'), findsOneWidget);
        expect(submissions, 1);
      },
    );
  });

  testWidgets('fewer than ten points disables redemption', (tester) async {
    var submissions = 0;
    await withRewards(
      tester,
      points: 9,
      redeem: (_) async {
        submissions++;
        return rewardResponse();
      },
      interact: () async {
        expect(
          find.text('1 more point to choose your free item.'),
          findsOneWidget,
        );
        final button = find.widgetWithText(ElevatedButton, 'Redeem');
        expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(submissions, 0);
      },
    );
  });

  testWidgets('cancelling the item chooser does not spend points', (
    tester,
  ) async {
    var submissions = 0;
    await withRewards(
      tester,
      points: 10,
      redeem: (_) async {
        submissions++;
        return rewardResponse(points: 0);
      },
      interact: () async {
        await tester.tap(find.text('Redeem'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Croissant'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.textContaining('1 free item available'), findsOneWidget);
        expect(submissions, 0);
      },
    );
  });

  testWidgets('a pending redemption prevents duplicates and dismissal', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    var submissions = 0;
    await withRewards(
      tester,
      points: 25,
      redeem: (_) {
        submissions++;
        return response.future;
      },
      interact: () async {
        await tester.tap(find.text('Redeem'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Croissant'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(
          ElevatedButton,
          'Redeem for 10 points',
        );
        await tester.tap(confirm);
        await tester.pump();
        expect(submissions, 1);
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        expect(tester.widget<TextButton>(cancel).onPressed, isNull);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(submissions, 1);

        response.complete(rewardResponse());
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(submissions, 1);
      },
    );
  });

  testWidgets('a rejected redemption keeps the choice and allows retry', (
    tester,
  ) async {
    var submissions = 0;
    await withRewards(
      tester,
      points: 25,
      redeem: (_) async {
        submissions++;
        if (submissions == 1) {
          return jsonResponse({
            'status': 'error',
            'message': 'The item is temporarily unavailable.',
          }, status: 400);
        }
        return rewardResponse();
      },
      interact: () async {
        await tester.tap(find.text('Redeem'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Croissant'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(
          ElevatedButton,
          'Redeem for 10 points',
        );
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text('The item is temporarily unavailable.'),
          findsOneWidget,
        );
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(submissions, 2);
      },
    );
  });
}
