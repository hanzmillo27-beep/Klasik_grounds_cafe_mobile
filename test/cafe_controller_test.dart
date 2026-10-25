import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/controller/cafe_controller.dart';
import 'package:klasik_grounds/services/api_service.dart';
import 'package:klasik_grounds/services/rate_limiter.dart';

void main() {
  const product = CafeProduct(
    id: '1',
    name: 'Latte',
    category: 'Coffee',
    description: 'Coffee with milk',
    price: 120,
    isAvailable: true,
  );

  CafeController controllerWith(
    Future<http.Response> Function(http.Request) respond,
  ) {
    final service = ApiService(
      client: MockClient(respond),
      rateLimiter: RateLimiter(),
    );
    final controller = CafeController(service: service, session: null)
      ..loading = false
      ..products = [product]
      ..addToCart(product);
    addTearDown(controller.dispose);
    addTearDown(service.close);
    return controller;
  }

  http.Response jsonResponse(Map<String, dynamic> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  test('rejected checkout keeps the cart and page available', () async {
    final controller = controllerWith((request) async {
      expect(request.method, 'POST');
      return jsonResponse({
        'status': 'error',
        'success': false,
        'message': 'Out of stock',
      });
    });

    await expectLater(
      controller.submitOrder(customerName: 'Guest'),
      throwsA(anything),
    );

    expect(controller.quantityFor(product), 1);
    expect(controller.errorMessage, isNull);
    expect(controller.orderErrorMessage, contains('Out of stock'));
    expect(controller.lastOrderId, isNull);
    expect(controller.loading, isFalse);
    expect(controller.placingOrder, isFalse);
  });

  test(
    'confirmed checkout stores the receipt without reloading the page',
    () async {
      final requests = <http.Request>[];
      final controller = controllerWith((request) async {
        requests.add(request);
        return jsonResponse({
          'status': 'success',
          'reference_code': 'KG-42',
          'total_amount': 120,
        });
      });
      final loadingStates = <bool>[];
      controller.addListener(() => loadingStates.add(controller.loading));

      expect(await controller.submitOrder(customerName: 'Guest'), 'KG-42');

      expect(requests, hasLength(1));
      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/Kiosk/submit');
      expect(loadingStates, everyElement(isFalse));
      expect(controller.cartItemCount, 0);
      expect(controller.lastOrderId, 'KG-42');
      expect(controller.orderErrorMessage, isNull);
      expect(controller.errorMessage, isNull);
      expect(controller.placingOrder, isFalse);

      controller.startNewOrder();
      expect(controller.lastOrderId, isNull);
      expect(controller.orderErrorMessage, isNull);
    },
  );

  test('only one submission runs and its cart stays unchanged', () async {
    final response = Completer<http.Response>();
    final requestStarted = Completer<void>();
    var requestCount = 0;
    final controller = controllerWith((request) {
      requestCount++;
      requestStarted.complete();
      return response.future;
    });
    final submission = controller.submitOrder(customerName: 'Guest');
    await requestStarted.future;
    expect(controller.placingOrder, isTrue);

    await expectLater(
      controller.submitOrder(customerName: 'Guest'),
      throwsA(isA<StateError>()),
    );
    controller.addToCart(product);
    controller.removeFromCart(product);
    controller.clearCart();
    controller.orderErrorMessage = 'Keep this pending message';
    controller.startNewOrder();

    expect(controller.quantityFor(product), 1);
    expect(controller.orderErrorMessage, 'Keep this pending message');
    expect(requestCount, 1);

    response.complete(
      jsonResponse({
        'status': 'success',
        'reference_code': 'KG-43',
        'total_amount': 120,
      }),
    );
    expect(await submission, 'KG-43');
    expect(requestCount, 1);
    expect(controller.cartItemCount, 0);
    expect(controller.lastOrderId, 'KG-43');
    expect(controller.placingOrder, isFalse);
  });

  test('starting a new order dismisses checkout feedback', () {
    final controller = controllerWith((_) async => jsonResponse({}));
    controller.lastOrderId = 'KG-44';
    controller.orderErrorMessage = 'Previous checkout message';
    var changes = 0;
    controller.addListener(() => changes++);

    controller.startNewOrder();

    expect(controller.lastOrderId, isNull);
    expect(controller.orderErrorMessage, isNull);
    expect(controller.cartItemCount, 1);
    expect(changes, 1);
  });
}
