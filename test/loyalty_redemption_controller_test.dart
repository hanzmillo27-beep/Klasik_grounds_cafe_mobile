import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/controller/cafe_controller.dart';
import 'package:klasik_grounds/services/api_service.dart';

void main() {
  const member = CafeSession(
    userId: 7,
    username: 'Alex',
    role: 'loyal_customer',
    sessionCookie: 'PHPSESSID=member',
  );
  const latte = CafeProduct(
    id: '1',
    name: 'Latte',
    category: 'Coffee',
    description: 'Coffee with milk',
    price: 120,
    isAvailable: true,
  );
  const cheesecake = CafeProduct(
    id: '2',
    name: 'Cheesecake',
    category: 'Food',
    description: 'A slice of cake',
    price: 150,
    isAvailable: true,
  );
  const unavailable = CafeProduct(
    id: '3',
    name: 'Sold out',
    category: 'Food',
    description: '',
    price: 100,
    isAvailable: false,
  );

  http.Response jsonResponse(Object? body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  http.Response receipt(
    CafeProduct product,
    int points, {
    String code = 'GC-TEST',
  }) => jsonResponse({
    'status': 'success',
    'data': {
      'reward_code': code,
      'product_id': int.parse(product.id),
      'product_name': product.name,
      'points': points,
      'points_spent': 10,
    },
  });

  CafeController controllerWith(
    Future<http.Response> Function(http.Request) respond, {
    int points = 27,
    CafeSession? session = member,
  }) {
    final service = ApiService(client: MockClient(respond));
    final controller = CafeController(service: service, session: session)
      ..loading = false
      ..products = [latte, cheesecake, unavailable]
      ..profile = MemberProfile(fullName: 'Alex', loyaltyPoints: points)
      ..addToCart(latte);
    addTearDown(controller.dispose);
    addTearDown(service.close);
    return controller;
  }

  test(
    'each 10 points allows another chosen item and preserves the cart',
    () async {
      var requests = 0;
      final controller = controllerWith((request) async {
        requests++;
        expect(
          (jsonDecode(request.body) as Map)['product_id'],
          requests == 1 ? 2 : 1,
        );
        return requests == 1
            ? receipt(cheesecake, 17, code: 'GC-CAKE')
            : receipt(latte, 7, code: 'GC-LATTE');
      });

      expect(controller.rewardsAvailable, 2);
      expect(controller.canRedeemReward, isTrue);

      final first = await controller.redeemReward(cheesecake);
      expect(first.productName, 'Cheesecake');
      expect(controller.profile.loyaltyPoints, 17);
      expect(controller.rewardsAvailable, 1);
      expect(controller.profile.redemptionsCount, 1);
      expect(controller.lastRedemption?.rewardCode, 'GC-CAKE');

      await controller.redeemReward(latte);
      expect(controller.profile.loyaltyPoints, 7);
      expect(controller.rewardsAvailable, 0);
      expect(controller.pointsToNextReward, 3);
      expect(controller.profile.redemptionsCount, 2);
      expect(controller.lastRedemption?.rewardCode, 'GC-LATTE');
      expect(controller.canRedeemReward, isFalse);
      expect(controller.quantityFor(latte), 1);
      expect(requests, 2);

      await expectLater(
        controller.redeemReward(latte),
        throwsA(isA<StateError>()),
      );
      expect(requests, 2);
    },
  );

  test(
    'uses the server balance when another device changed the points',
    () async {
      final controller = controllerWith((_) async => receipt(latte, 4));

      await controller.redeemReward(latte);

      expect(controller.profile.loyaltyPoints, 4);
      expect(controller.rewardsAvailable, 0);
      expect(controller.lastRedemption?.points, 4);
    },
  );

  test('insufficient points never starts a redemption', () async {
    var requests = 0;
    final controller = controllerWith((_) async {
      requests++;
      return receipt(latte, 0);
    }, points: 9);

    expect(controller.canRedeemReward, isFalse);
    await expectLater(
      controller.redeemReward(latte),
      throwsA(isA<StateError>()),
    );
    expect(requests, 0);
    expect(controller.profile.loyaltyPoints, 9);
    expect(controller.redeemingReward, isFalse);
  });

  test('guests and nonloyalty accounts cannot redeem points', () async {
    var requests = 0;
    for (final session in <CafeSession?>[
      null,
      const CafeSession(
        userId: 8,
        username: 'Guest account',
        role: 'user',
        sessionCookie: 'PHPSESSID=user',
      ),
    ]) {
      final controller = controllerWith((_) async {
        requests++;
        return receipt(latte, 17);
      }, session: session);

      expect(controller.canRedeemReward, isFalse);
      await expectLater(
        controller.redeemReward(latte),
        throwsA(isA<StateError>()),
      );
      expect(controller.profile.loyaltyPoints, 27);
    }
    expect(requests, 0);
  });

  test('selection must be an available item in the loaded catalog', () async {
    var requests = 0;
    final controller = controllerWith((_) async {
      requests++;
      return receipt(latte, 17);
    });
    const unknown = CafeProduct(
      id: '99',
      name: 'Not in the menu',
      category: 'Food',
      description: '',
      price: 1,
      isAvailable: true,
    );
    // Supplying an available-looking object does not bypass catalog availability.
    const disguised = CafeProduct(
      id: '3',
      name: 'Sold out',
      category: 'Food',
      description: '',
      price: 1,
      isAvailable: true,
    );

    for (final product in [unavailable, unknown, disguised]) {
      await expectLater(
        controller.redeemReward(product),
        throwsA(isA<StateError>()),
      );
    }
    expect(requests, 0);
    expect(controller.profile.loyaltyPoints, 27);
    controller.products = [unavailable];
    expect(controller.canRedeemReward, isFalse);
  });

  test('blocks duplicate submissions while a redemption is pending', () async {
    final pendingResponse = Completer<http.Response>();
    final requestStarted = Completer<void>();
    var requests = 0;
    final controller = controllerWith((_) {
      requests++;
      requestStarted.complete();
      return pendingResponse.future;
    });

    final redemption = controller.redeemReward(latte);
    await requestStarted.future;
    expect(controller.redeemingReward, isTrue);
    expect(controller.canRedeemReward, isFalse);
    expect(controller.profile.loyaltyPoints, 27);
    await expectLater(
      controller.redeemReward(cheesecake),
      throwsA(isA<StateError>()),
    );
    expect(requests, 1);

    pendingResponse.complete(receipt(latte, 17));
    await redemption;
    expect(controller.profile.loyaltyPoints, 17);
    expect(controller.redeemingReward, isFalse);
    expect(controller.canRedeemReward, isTrue);
    expect(controller.quantityFor(latte), 1);
  });

  test(
    'a failed redemption preserves balance and cart and can be retried',
    () async {
      var requests = 0;
      final controller = controllerWith((_) async {
        requests++;
        return requests == 1
            ? jsonResponse({'status': 'error', 'message': 'Out of stock'})
            : receipt(cheesecake, 17);
      });

      await expectLater(
        controller.redeemReward(cheesecake),
        throwsA(isA<StateError>()),
      );

      expect(controller.profile.loyaltyPoints, 27);
      expect(controller.profile.redemptionsCount, 0);
      expect(controller.lastRedemption, isNull);
      expect(controller.redemptionErrorMessage, 'Out of stock');
      expect(controller.errorMessage, isNull);
      expect(controller.quantityFor(latte), 1);
      expect(controller.redeemingReward, isFalse);
      expect(controller.canRedeemReward, isTrue);

      await controller.redeemReward(cheesecake);
      expect(controller.profile.loyaltyPoints, 17);
      expect(controller.redemptionErrorMessage, isNull);
      expect(controller.lastRedemption?.productName, 'Cheesecake');
      expect(requests, 2);
    },
  );

  test(
    'a later rejection retains the previous successful reward receipt',
    () async {
      var requests = 0;
      final controller = controllerWith((_) async {
        requests++;
        return requests == 1
            ? receipt(latte, 17, code: 'GC-KEEP')
            : jsonResponse({'status': 'error', 'message': 'Try again later.'});
      });

      await controller.redeemReward(latte);
      await expectLater(
        controller.redeemReward(cheesecake),
        throwsA(isA<StateError>()),
      );

      expect(controller.lastRedemption?.rewardCode, 'GC-KEEP');
      expect(controller.profile.loyaltyPoints, 17);
      expect(controller.profile.redemptionsCount, 1);
      expect(controller.redemptionErrorMessage, 'Try again later.');
      expect(controller.redeemingReward, isFalse);
    },
  );
}
