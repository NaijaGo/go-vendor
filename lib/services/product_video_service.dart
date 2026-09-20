import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';

class ProductVideoService {
  final http.Client _client = http.Client();
  Map<String, dynamic>? _ticket;
  String? _filePath;
  bool _uploaded = false;

  void dispose() => _client.close();
  void resetUpload() {
    _ticket = null;
    _filePath = null;
    _uploaded = false;
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('Please sign in again to upload a video.');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    final uri = Uri.parse('$baseUrl/api/product-media$path');
    final response =
        await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 40));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        data['message'] ?? 'Unable to process this video. Please retry.',
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> configuration() =>
      _request('/config', authenticated: false);
  Future<Map<String, dynamic>> asset(String id) => _request('/assets/$id');

  Future<Map<String, dynamic>> upload(
    XFile file,
    String mimeType,
    String policyVersion,
    void Function(String) onStatus,
  ) async {
    if (_filePath != file.path) resetUpload();
    _filePath = file.path;
    onStatus('Preparing secure upload...');
    _ticket ??= await _request(
      '/uploads',
      body: {
        'mimeType': mimeType,
        'bytes': await file.length(),
        'policyVersion': policyVersion,
      },
    );
    final assetId = _ticket!['assetId'].toString();
    if (!_uploaded) {
      onStatus('Uploading and preparing video. Keep this page open...');
      final uploadUri = Uri.parse(_ticket!['uploadUrl'].toString());
      if (uploadUri.scheme != 'https' ||
          uploadUri.host != 'api.cloudinary.com') {
        throw Exception('The upload address could not be verified.');
      }
      final request = http.MultipartRequest('POST', uploadUri);
      request.fields.addAll(
        Map<String, dynamic>.from(
          _ticket!['fields'] as Map,
        ).map((key, value) => MapEntry(key, value.toString())),
      );
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType.parse(mimeType),
        ),
      );
      // This request contains Cloudinary's scoped signature, never the app JWT.
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(minutes: 10)),
      ).timeout(const Duration(minutes: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Video upload failed. Check your connection and retry.',
        );
      }
      _uploaded = true;
    }
    onStatus('Verifying video length and quality...');
    final result = await _request('/assets/$assetId/complete', body: {});
    if (!['pending_review', 'approved'].contains(result['status'])) {
      throw Exception(
        result['rejectionReason'] ?? 'This video could not be accepted.',
      );
    }
    return result;
  }
}
