import 'package:flutter_test/flutter_test.dart';
import 'package:lifequest/main.dart';

void main() {
  testWidgets('shows the LifeQuest home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LifeQuestApp());

    expect(find.text('LifeQuest'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Missões'), findsOneWidget);
  });
}
