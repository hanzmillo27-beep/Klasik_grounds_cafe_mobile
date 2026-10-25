import 'package:flutter_test/flutter_test.dart';
import 'package:klasik_grounds/main.dart';

void main() {
  testWidgets('shows sign in and guest access', (tester) async {
    await tester.pumpWidget(const KlasikGroundsApp());

    expect(find.text('Sign In?'), findsOneWidget);
    expect(find.text('Start an Order'), findsOneWidget);
  });
}
