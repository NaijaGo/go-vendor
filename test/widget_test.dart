import 'package:flutter_test/flutter_test.dart';
import 'package:naijagovendorsapp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('vendor app starts', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const NaijaGoVendorsApp());
    await tester.pumpAndSettle();

    expect(find.byType(NaijaGoVendorsApp), findsOneWidget);
  });
}
