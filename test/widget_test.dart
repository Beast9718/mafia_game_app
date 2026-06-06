import 'package:flutter_test/flutter_test.dart';
import 'package:mafia_night_has_come/main.dart';

void main() {
  testWidgets('App load smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MafiaGameApp());
    expect(find.byType(MafiaGameApp), findsOneWidget);
  });
}
