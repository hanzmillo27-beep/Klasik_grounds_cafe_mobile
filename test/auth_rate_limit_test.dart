import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klasik_grounds/home_page/auth_page.dart';

void main() {
  testWidgets(
    'sign-in cooldown blocks taps and Enter while guest stays available',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loginPageRequests = 0;
      var loginRequests = 0;
      var guestSelections = 0;
      final firstLoginPage = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/Auth') {
          loginPageRequests++;
          if (loginPageRequests == 1) return firstLoginPage.future;
          return http.Response(
            '',
            200,
            headers: {'set-cookie': 'PHPSESSID=test; Path=/'},
          );
        }
        expect(request.method, 'POST');
        expect(request.url.path, '/Auth/login');
        loginRequests++;
        return http.Response('', 302, headers: {'location': '/Auth'});
      });
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final signInButton = find.widgetWithText(ElevatedButton, 'Sign in');

      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: AuthPage(
              onSignedIn: (_) => fail('Invalid credentials must not sign in.'),
              onContinueAsGuest: () => guestSelections++,
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'),
          'guest',
        );
        await tester.enterText(passwordField, 'wrong-password');
        await tester.tap(signInButton);
        await tester.pump();
        expect(loginPageRequests, 1);
        expect(loginRequests, 0);

        // The keyboard can still invoke onFieldSubmitted while a button is disabled.
        await tester.showKeyboard(passwordField);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(loginPageRequests, 1);
        firstLoginPage.complete(
          http.Response(
            '',
            200,
            headers: {'set-cookie': 'PHPSESSID=test; Path=/'},
          ),
        );
        await tester.pumpAndSettle();
        expect(loginRequests, 1);
        expect(find.textContaining('Bad state:'), findsNothing);

        for (var attempt = 2; attempt <= 5; attempt++) {
          await tester.tap(signInButton);
          await tester.pumpAndSettle();
        }
        expect(loginPageRequests, 10);
        expect(loginRequests, 5);

        await tester.tap(signInButton);
        await tester.pumpAndSettle();
        expect(loginPageRequests, 10);
        expect(loginRequests, 5);
        final cooldownLabel = tester
            .widget<Text>(find.textContaining(RegExp(r'^Try again in \d+s$')))
            .data!;
        final initialSeconds = int.parse(
          RegExp(r'Try again in (\d+)s').firstMatch(cooldownLabel)![1]!,
        );
        expect(initialSeconds, inInclusiveRange(1, 60));
        final cooldownButton = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, cooldownLabel),
        );
        expect(cooldownButton.onPressed, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Start an Order'),
              )
              .onPressed,
          isNotNull,
        );

        await tester.showKeyboard(passwordField);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(loginPageRequests, 10);
        expect(loginRequests, 5);
        await tester.pump(const Duration(seconds: 1));
        expect(
          find.text('Try again in ${initialSeconds - 1}s'),
          findsOneWidget,
        );

        await tester.tap(find.text('Start an Order'));
        await tester.pump();
        expect(guestSelections, 1);

        // Disposing during cooldown must cancel the periodic timer.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 61));
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );
}
