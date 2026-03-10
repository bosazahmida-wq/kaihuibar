import 'package:flutter_test/flutter_test.dart';

import 'package:kaihuibar_mobile/main.dart';

void main() {
  testWidgets('App starts at home with bottom tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const KaihuiBarApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 1200));

    expect(find.text('开会吧'), findsOneWidget);
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('好友'), findsWidgets);
  });
}
