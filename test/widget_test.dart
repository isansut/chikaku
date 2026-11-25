import 'package:flutter_test/flutter_test.dart';
import 'package:chikaku/main.dart';

void main() {
  testWidgets('ChikakuApp renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ChikakuApp());
    expect(find.byType(ChikakuApp), findsOneWidget);
  });
}
