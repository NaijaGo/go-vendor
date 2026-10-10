import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:naijagovendorsapp/screens/vendor/add_product_screen.dart';

void main() {
  testWidgets(
    'vendor can select the same creator equipment category as customers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: AddProductScreen()));
      await tester.pump();
      const category = 'Photography > Content Creator Equipment';
      final selector = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButton<String> &&
            (widget.items?.any((item) => item.value == category) ?? false),
      );
      expect(selector, findsOneWidget);
      final dropdown = tester.widget<DropdownButton<String>>(selector);
      expect(
        dropdown.items!.where((item) => item.value == category),
        hasLength(1),
      );
      expect(
        dropdown.items!.where((item) => item.value == category).single.enabled,
        isTrue,
      );
      dropdown.onChanged!(category);
      await tester.pump();
      expect(tester.widget<DropdownButton<String>>(selector).value, category);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
