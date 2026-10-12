import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:naijagovendorsapp/screens/vendor/add_product_screen.dart';
import 'package:naijagovendorsapp/models/product.dart';

void main() {
  for (final status in [
    'approved',
    'none',
    'reviewing',
    'rejected',
    'suspended',
  ]) {
    testWidgets(
      'saved medicine flags retain UI protection for pharmacist $status',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'user': jsonEncode({
            'isVendor': true,
            'vendorStatus': 'approved',
            'isPharmacist': true,
            'role': 'pharmacist',
            'pharmacistStatus': status,
          }),
        });
        final product = Product(
          id: 'fixture',
          name: 'Fixture',
          description: 'Fixture',
          price: 1,
          category: 'Legacy Parent',
          stockQuantity: 1,
          vendorId: 'vendor',
          requiresPrescription: true,
        );
        await tester.pumpWidget(
          MaterialApp(home: AddProductScreen(initialProduct: product)),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(
          find.text(
            status == 'approved' || status == 'none'
                ? 'Medicine access settings'
                : 'Pharmacist approval required',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'contradictory legacy food keeps restaurant information visible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final product = Product(
        id: 'fixture',
        name: 'Fixture',
        description: 'Fixture',
        price: 1,
        category: 'Restaurant',
        subcategory: 'Restaurant Equipment',
        stockQuantity: 1,
        vendorId: 'vendor',
      );
      await tester.pumpWidget(
        MaterialApp(home: AddProductScreen(initialProduct: product)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Restaurant ordering'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final fields in [
    ['Legacy Parent', 'Legacy Child'],
    ['Health & Beauty', 'Medicine'],
    ['Fashion > Men', ''],
  ]) {
    testWidgets('editing retains legacy selection ${fields.join(" / ")}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final product = Product(
        id: 'fixture',
        name: 'Fixture',
        description: 'Fixture',
        price: 1,
        category: fields[0],
        subcategory: fields[1],
        stockQuantity: 1,
        vendorId: 'vendor',
      );
      await tester.pumpWidget(
        MaterialApp(home: AddProductScreen(initialProduct: product)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      final expected = fields[0].contains('>') || fields[1].isEmpty
          ? fields[0]
          : '${fields[0]} > ${fields[1]}';
      final selector = find.byWidgetPredicate(
        (widget) =>
            widget is DropdownButton<String> && widget.value == expected,
      );
      expect(selector, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'vendor can select the same creator equipment category as customers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const MaterialApp(home: AddProductScreen()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
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
