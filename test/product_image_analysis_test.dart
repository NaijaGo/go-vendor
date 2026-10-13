import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:naijagovendorsapp/models/catalog_category.dart';
import 'package:naijagovendorsapp/models/product.dart';
import 'package:naijagovendorsapp/services/product_image_analysis_service.dart';
import 'package:naijagovendorsapp/screens/vendor/add_product_screen.dart';

class FixtureAnalysis extends ProductImageAnalysisService {
  FixtureAnalysis(this.handler);
  final Future<ProductImageSuggestion> Function() handler;
  int calls = 0;
  @override
  Future<ProductImageSuggestion> analyze(File image, String token) async {
    calls++;
    return handler();
  }
}

void main() {
  final data =
      jsonDecode(File('assets/catalog_taxonomy.v1.json').readAsStringSync())
          as Map<String, dynamic>;
  final hierarchy = CatalogHierarchy.fromJson(data);
  final parent = (data['categories'] as List).firstWhere(
    (row) => row['label'] == 'Photography',
  );
  final child = (parent['children'] as List).firstWhere(
    (row) => row['label'] == 'Content Creator Equipment',
  );
  Map<String, dynamic> result({String name = 'Ring light'}) => {
    'suggestions': {
      'name': name,
      'description': 'A black circular light.',
      'brand': '',
      'searchTags': ['ring light'],
      'specifications': {'colour': 'black'},
      'price': 99,
    },
    'classification': {
      'categoryId': parent['id'],
      'subcategoryId': child['id'],
      'category': parent['label'],
      'subcategory': child['label'],
    },
    'taxonomyChecksum': hierarchy.checksum,
    'needsManualCategory': false,
    'warnings': <String>[],
    'reviewRequired': true,
    'possibleDuplicates': [],
  };
  const blank = {
    'name': '',
    'description': '',
    'brand': '',
    'searchTags': '',
    'specifications': '',
    'category': '',
    'price': '200',
    'stock': '5',
  };

  test(
    'autofill uses actual taxonomy, with references disabled, and excludes commercial fields',
    () {
      final fields = ProductImageSuggestion(
        result(),
      ).fieldsFor(blank, blank, hierarchy);
      expect(fields['category'], 'Photography > Content Creator Equipment');
      expect(fields['name'], 'Ring light');
      expect(fields.containsKey('price'), isFalse);
      expect(fields.containsKey('stock'), isFalse);
      expect(hierarchy.referencesReady, isFalse);
    },
  );
  test('manual edits and existing listings are preserved', () {
    final s = ProductImageSuggestion(result());
    final fields = s.fieldsFor(
      {...blank, 'name': 'Manual', 'category': 'Fashion'},
      blank,
      hierarchy,
    );
    expect(fields.containsKey('name'), isFalse);
    expect(fields.containsKey('category'), isFalse);
    expect(s.fieldsFor(blank, blank, hierarchy, editing: true), isEmpty);
  });
  test(
    'uncertain, stale or mismatched classifications require manual selection',
    () {
      for (final changes in [
        {'needsManualCategory': true},
        {'taxonomyChecksum': 'stale'},
        {
          'classification': {'categoryId': 'invalid'},
        },
      ]) {
        expect(
          ProductImageSuggestion({
            ...result(),
            ...changes,
          }).fieldsFor(blank, blank, hierarchy).containsKey('category'),
          isFalse,
        );
      }
    },
  );
  test(
    'analysis sends one photo and backend bearer token without provider secrets',
    () async {
      final dir = await Directory.systemTemp.createTemp('naijago-ai-fixture-');
      addTearDown(() => dir.delete(recursive: true));
      final image = await File(
        '${dir.path}/photo.jpg',
      ).writeAsBytes([255, 216, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/products/image-analysis');
        expect(request.headers['Authorization'], 'Bearer fixture-token');
        expect(latin1.decode(request.bodyBytes), contains('name="image"'));
        expect(request.headers.containsKey('x-api-key'), isFalse);
        return http.Response(jsonEncode(result()), 200);
      });
      addTearDown(client.close);
      final suggestion = await ProductImageAnalysisService(
        client: client,
      ).analyze(image, 'fixture-token');
      expect(suggestion.data['suggestions']['name'], 'Ring light');
      expect(calls, 1);
    },
  );
  test(
    'oversized photos never reach HTTP, and failed/invalid analysis keeps manual path',
    () async {
      final dir = await Directory.systemTemp.createTemp('naijago-ai-fixture-');
      addTearDown(() => dir.delete(recursive: true));
      final image = await File(
        '${dir.path}/photo.jpg',
      ).writeAsBytes(List.filled(5 * 1024 * 1024 + 1, 0));
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{"message":"Unavailable"}', 503);
      });
      addTearDown(client.close);
      final service = ProductImageAnalysisService(client: client);
      await expectLater(
        service.analyze(image, 'fixture'),
        throwsFormatException,
      );
      expect(calls, 0);
      await image.writeAsBytes([1, 2, 3]);
      await expectLater(
        service.analyze(image, 'fixture'),
        throwsFormatException,
      );
      expect(calls, 1);
      final invalid = MockClient((request) async => http.Response('{}', 200));
      addTearDown(invalid.close);
      await expectLater(
        ProductImageAnalysisService(client: invalid).analyze(image, 'fixture'),
        throwsFormatException,
      );
    },
  );

  Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
  String text(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!.text;
  Future<void> mount(
    WidgetTester tester,
    FixtureAnalysis service, {
    Product? product,
  }) async {
    SharedPreferences.setMockInitialValues({'jwt_token': 'fixture-token'});
    await tester.pumpWidget(
      MaterialApp(
        home: AddProductScreen(
          initialProduct: product,
          imageAnalysisService: service,
          pickMainImage: () async => File('assets/govendors.png'),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
  }

  Future<void> select(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('selectMainProductImage')));
    await tester.tap(find.byKey(const Key('selectMainProductImage')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  testWidgets(
    'vendor form visibly offers AI suggestions while preserving existing commercial fields',
    (tester) async {
      final service = FixtureAnalysis(
        () async => ProductImageSuggestion(result()),
      );
      final product = Product(
        id: 'fixture',
        name: 'Original',
        description: 'Original details',
        price: 200,
        category: 'Photography > Content Creator Equipment',
        stockQuantity: 5,
        vendorId: 'vendor',
      );
      await mount(tester, service, product: product);
      expect(find.text('AI photo suggestions'), findsOneWidget);
      expect(text(tester, 'Product Name'), 'Original');
      expect(text(tester, 'Price'), '200.00');
      await select(tester);
      expect(service.calls, 1);
      expect(text(tester, 'Product Name'), 'Original');
      await tester.ensureVisible(find.text('Use suggestions in this form'));
      await tester.tap(find.text('Use suggestions in this form'));
      await tester.pump();
      expect(text(tester, 'Product Name'), 'Ring light');
      expect(text(tester, 'Price'), '200.00');
      final review = find.widgetWithText(
        CheckboxListTile,
        'I checked the suggested details and selected the correct category',
      );
      expect(tester.widget<CheckboxListTile>(review).value, isFalse);
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Add Product'),
          )
          .onPressed!();
      await tester.pump();
      expect(
        find.textContaining('review the suggested details before saving'),
        findsOneWidget,
      );
      tester.widget<CheckboxListTile>(review).onChanged!(true);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(review).value, isTrue);
      await tester.ensureVisible(field('Product Name'));
      await tester.enterText(field('Product Name'), 'Reviewed and edited');
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(review).value, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'legacy fashion edits retain optional missing sizes and saved colours',
    (tester) async {
      final service = FixtureAnalysis(
        () async => ProductImageSuggestion(result()),
      );
      final product = Product(
        id: 'fixture',
        name: 'Legacy shoes',
        description: 'Unchanged details',
        price: 200,
        category: 'Fashion > Footwear',
        stockQuantity: 5,
        vendorId: 'vendor',
        availableColors: const ['Black'],
      );
      await mount(tester, service, product: product);
      expect(text(tester, 'Available colours (optional)'), 'Black');
      expect(find.text('Available Sizes (Optional)'), findsOneWidget);
      expect(text(tester, 'Price'), '200.00');
      expect(service.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'new-product image autofills visible details but not price or stock',
    (tester) async {
      final service = FixtureAnalysis(
        () async => ProductImageSuggestion(result()),
      );
      await mount(tester, service);
      await select(tester);
      expect(text(tester, 'Product Name'), 'Ring light');
      expect(text(tester, 'Price'), '');
      expect(text(tester, 'Stock Quantity'), '');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButton<String> &&
              widget.value == 'Photography > Content Creator Equipment',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'I checked the suggested details and selected the correct category',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('manual typing while analysis runs is never overwritten', (
    tester,
  ) async {
    final pending = Completer<ProductImageSuggestion>();
    final service = FixtureAnalysis(() => pending.future);
    await mount(tester, service);
    await select(tester);
    await tester.ensureVisible(field('Product Name'));
    await tester.enterText(field('Product Name'), 'Manual name');
    pending.complete(ProductImageSuggestion(result()));
    await tester.pump();
    expect(text(tester, 'Product Name'), 'Manual name');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('a newer photo discards the first analysis response', (
    tester,
  ) async {
    final pending = [
      Completer<ProductImageSuggestion>(),
      Completer<ProductImageSuggestion>(),
    ];
    var index = 0;
    final service = FixtureAnalysis(() => pending[index++].future);
    await mount(tester, service);
    await select(tester);
    await select(tester);
    pending[1].complete(ProductImageSuggestion(result(name: 'Newest')));
    await tester.pump();
    pending[0].complete(ProductImageSuggestion(result()));
    await tester.pump();
    expect(text(tester, 'Product Name'), 'Newest');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('provider failure leaves the manual form usable', (tester) async {
    final service = FixtureAnalysis(
      () async => throw const FormatException('Unavailable'),
    );
    await mount(tester, service);
    await select(tester);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(text(tester, 'Product Name'), '');
    expect(
      find.text(
        'I checked the suggested details and selected the correct category',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
