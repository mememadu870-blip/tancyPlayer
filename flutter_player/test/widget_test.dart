import 'package:flutter_test/flutter_test.dart';
import 'package:tancy_player/main.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const TancyApp());
    expect(find.text('tancyPlayer'), findsOneWidget);
  });
}
