// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:gpmt/main.dart';
import 'package:gpmt/utils/constants.dart';

void main() {
  testWidgets('WinRAR app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WinRARApp(enableBackgroundInit: false));
    await tester.pump();

    // Verify that the toolbar exists.
    expect(find.text(AppStrings.add), findsOneWidget);
    expect(find.text(AppStrings.extractToLabel), findsOneWidget);

    // Verify column headers
    expect(find.textContaining(AppStrings.colName), findsOneWidget);
    expect(find.textContaining(AppStrings.colSize), findsOneWidget);
  });
}
