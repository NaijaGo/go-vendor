import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import 'package:image_picker/image_picker.dart';

class ExploreException implements Exception {
  const ExploreException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ExploreService {
  ExploreService({http.Client? client, Future<String?> Function()? tokenReader})
    : _client = client ?? http.Client(),
      _tokenReader = tokenReader ?? _readToken;
  final http.Client _client;
  final Future<String?> Function() _tokenReader;
  static Future<String?> _readToken() async =>
      (await SharedPreferences.getInstance()).getString('jwt_token');

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    final token = authenticated ? await _tokenReader() : null;
    if (authenticated && (token == null || token.isEmpty)) {
      throw const ExploreException('Please sign in to use Explore.');
    }
    final uri = Uri.parse(
      '$baseUrl/api/explore/$path',
    ).replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      final data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data['message'];
        throw ExploreException(
          response.statusCode < 500 &&
                  message is String &&
                  message.length <= 200
              ? message
              : 'Unable to connect to Explore. Check your internet and try again.',
        );
      }
      return data;
    } on ExploreException {
      rethrow;
    } catch (_) {
      throw const ExploreException(
        'Unable to connect to Explore. Check your internet and try again.',
      );
    }
  }

  Future<Map<String, dynamic>> config() =>
      request('config', authenticated: false);

  Future<Map<String, dynamic>> myVideos({int page = 1}) =>
      request('videos/mine', query: {'page': '$page', 'limit': '20'});

  Future<List<Map<String, dynamic>>> myProducts() async {
    final token = await _tokenReader();
    if (token == null || token.isEmpty) throw const ExploreException('Please sign in again.');
    try {
      final response = await _client.get(Uri.parse('$baseUrl/api/products/myproducts?limit=100'),
        headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw const ExploreException('Could not load your products. You can post without linking a product.');
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const ExploreException('Product response is unavailable.');
      return decoded.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['isActive'] == true &&
              (row['productStatus'] == null || row['productStatus'] == 'active') &&
              (row['moderationStatus'] == null || row['moderationStatus'] == 'approved')).toList();
    } on ExploreException { rethrow; }
    catch (_) { throw const ExploreException('Could not load your products. You can post without linking a product.'); }
  }

  Future<Map<String, dynamic>> publishVideo(XFile file, String caption, {String? productId}) async {
    if (caption.trim().isEmpty || caption.trim().length > 500) {
      throw const ExploreException('Enter a caption of 1–500 characters.');
    }
    if (await file.length() > 90 * 1024 * 1024) throw const ExploreException('Compress this video to 90 MB or less before uploading.');
    final token = await _tokenReader();
    if (token == null || token.isEmpty) throw const ExploreException('Please sign in again.');
    try {
      final upload = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/explore/videos'))
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['caption'] = caption.trim();
      if (productId != null) upload.fields['productId'] = productId;
      upload.files.add(await http.MultipartFile.fromPath('video', file.path, filename: file.name));
      final response = await _client.send(upload).then(http.Response.fromStream)
          .timeout(const Duration(minutes: 4));
      final decoded = jsonDecode(response.body);
      if (response.statusCode != 201) {
        final message = decoded is Map ? decoded['message'] : null;
        throw ExploreException(response.statusCode < 500 && message is String
            ? message : 'Video upload failed. Refresh My Videos before retrying.');
      }
      if (decoded is! Map || decoded['video'] is! Map) throw const ExploreException('Refresh My Videos to confirm your upload.');
      return Map<String, dynamic>.from(decoded['video'] as Map);
    } on ExploreException { rethrow; }
    catch (_) { throw const ExploreException('Upload could not be confirmed. Refresh My Videos before retrying.'); }
  }

  Future<void> unpublishVideo(String id) async {
    await request('videos/$id/unpublish', method: 'PATCH');
  }
  Future<void> deleteVideo(String id) async {
    await request(id, method: 'DELETE');
  }
  void dispose() => _client.close();
}
