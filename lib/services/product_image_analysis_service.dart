import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/catalog_category.dart';

class ProductImageSuggestion {
  ProductImageSuggestion(this.data);
  final Map<String, dynamic> data;
  List<String> get warnings => [
    ...List<String>.from(data['warnings'] ?? []),
    if ((data['possibleDuplicates'] as List? ?? []).isNotEmpty)
      'Possible duplicate listings found. Check your existing products before saving.',
  ];

  Map<String, String> fieldsFor(
    Map<String, String> current,
    Map<String, String> snapshot,
    CatalogHierarchy? hierarchy, {
    bool editing = false,
  }) {
    if (editing) return {};
    final s = Map<String, dynamic>.from(data['suggestions'] as Map);
    final candidate = <String, String>{
      'name': s['name'] as String? ?? '',
      'description': s['description'] as String? ?? '',
      'brand': s['brand'] as String? ?? '',
      'searchTags': (s['searchTags'] as List? ?? []).join(', '),
      'specifications': const JsonEncoder.withIndent(
        '  ',
      ).convert(s['specifications'] ?? {}),
    };
    final match = data['classification'] as Map?;
    final taxonomy = hierarchy?.toJson();
    if (data['needsManualCategory'] == false &&
        match != null &&
        data['taxonomyChecksum'] == taxonomy?['checksum'] &&
        current['category'] == snapshot['category']) {
      for (final parent in taxonomy?['categories'] as List? ?? []) {
        if (parent['id'] != match['categoryId'] ||
            parent['label'] != match['category']) {
          continue;
        }
        for (final child in parent['children'] as List) {
          if (child['id'] == match['subcategoryId'] &&
              child['label'] == match['subcategory']) {
            candidate['category'] = '${parent['label']} > ${child['label']}';
          }
        }
      }
    }
    return {
      for (final entry in candidate.entries)
        if (entry.value.isNotEmpty && current[entry.key] == snapshot[entry.key])
          entry.key: entry.value,
    };
  }
}

class ProductImageAnalysisService {
  ProductImageAnalysisService({http.Client? client}) : _client = client;
  final http.Client? _client;

  Future<ProductImageSuggestion> analyze(File image, String token) async {
    if (await image.length() > 5 * 1024 * 1024) {
      throw const FormatException(
        'AI accepts images up to 5 MB. Enter details manually.',
      );
    }
    final client = _client ?? http.Client();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/products/image-analysis'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          await image.readAsBytes(),
          filename: 'product-photo',
        ),
      );
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        throw FormatException(
          data['message'] as String? ??
              'Analysis unavailable. Enter details manually.',
        );
      }
      if (data['suggestions'] is! Map ||
          data['warnings'] is! List ||
          data['reviewRequired'] != true) {
        throw const FormatException(
          'Invalid AI suggestions. Enter details manually.',
        );
      }
      return ProductImageSuggestion(data);
    } finally {
      if (_client == null) client.close();
    }
  }
}
