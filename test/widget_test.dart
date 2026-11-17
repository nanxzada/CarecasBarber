
import 'package:flutter_test/flutter_test.dart';

import 'package:carecasbarber/main.dart';

void main() {
  testWidgets('CarecasApp builds without exploding', (WidgetTester tester) async {
    await tester.pumpWidget(const CarecasApp());
    expect(find.text("Careca's"), findsOneWidget);
  });
}
