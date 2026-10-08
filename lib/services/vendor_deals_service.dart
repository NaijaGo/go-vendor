import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/vendor_deal.dart';
import 'api_service.dart';

class VendorDealsException implements Exception {
  const VendorDealsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VendorDealsPage {
  const VendorDealsPage(this.deals, this.page, this.hasMore);
  final List<VendorDeal> deals;
  final int page;
  final bool hasMore;
}

class VendorDealsService {
  VendorDealsService({
    Future<http.Response> Function(String)? get,
    Future<http.Response> Function(String, Map)? post,
    Future<http.Response> Function(String, Map)? patch,
  }) : _get = get ?? ApiService.get,
       _post = post ?? ApiService.post,
       _patch = patch ?? ApiService.patch;
  final Future<http.Response> Function(String) _get;
  final Future<http.Response> Function(String, Map) _post, _patch;
  final Map<String, Future<Map<String, dynamic>?>> _products = {};
  void clearProducts() => _products.clear();
  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Map? body,
  }) async {
    try {
      final response =
          await (method == 'PATCH'
                  ? _patch(path, body!)
                  : method == 'POST'
                  ? _post(path, body!)
                  : _get(path))
              .timeout(const Duration(seconds: 20));
      if (response.statusCode == 401)
        throw const VendorDealsException(
          'Please sign in again to manage Deals.',
        );
      if (response.statusCode == 403)
        throw const VendorDealsException(
          'Only approved vendors can manage their own Deals.',
        );
      if (response.statusCode == 404)
        throw const VendorDealsException(
          'Deals or this product are not available on this server.',
        );
      if (response.statusCode >= 500)
        throw const VendorDealsException(
          'Deals are temporarily unavailable. Please try again.',
        );
      final data = jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data is Map ? data['message'] : null;
        throw VendorDealsException(
          message is String && message.length <= 200
              ? message
              : 'Could not save this Deal. Refresh and try again.',
        );
      }
      return data;
    } on VendorDealsException {
      rethrow;
    } catch (_) {
      throw VendorDealsException(
        method == 'GET'
            ? 'Unable to connect to Deals. Check your connection and try again.'
            : 'Could not confirm the save. Return to your Deals and refresh before retrying to avoid a duplicate submission.',
      );
    }
  }

  Future<VendorDealsPage> mine({int page = 1, String? status}) async {
    final query = Uri(
      queryParameters: {
        'page': '$page',
        'limit': '20',
        if (status != null) 'status': status,
      },
    ).query;
    final data = await _request('/api/deals/mine?$query');
    if (data is! Map ||
        data['deals'] is! List ||
        data['page'] != page ||
        data['hasMore'] is! bool) {
      throw const VendorDealsException(
        'The Deals response was invalid. Try refreshing.',
      );
    }
    return VendorDealsPage(
      (data['deals'] as List)
          .map((row) => VendorDeal.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
      page,
      data['hasMore'],
    );
  }

  Future<Map<String, dynamic>?> product(String id) =>
      _products.putIfAbsent(id, () async {
        try {
          return Map<String, dynamic>.from(
            await _request('/api/products/${dealId(id)}'),
          );
        } on VendorDealsException {
          return null;
        }
      });
  Future<String> vendorId() async {
    final user = await _request('/api/auth/me');
    if (user is! Map ||
        user['isVendor'] != true ||
        user['vendorStatus'] != 'approved') {
      throw const VendorDealsException(
        'Vendor approval is required to submit Deals.',
      );
    }
    return dealId(user['_id']);
  }

  Future<List<Map<String, dynamic>>> ownedProducts(int page) async {
    final data = await _request('/api/products/myproducts?page=$page&limit=50');
    if (data is! List)
      throw const VendorDealsException('Could not load your products.');
    return data.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Map<String, dynamic> fields(
    DealTarget target,
    String type,
    String value,
    DateTime start,
    DateTime end,
    String status, {
    bool creating = false,
  }) {
    if (!['draft', 'pending'].contains(status) ||
        DealPreview.calculate(target.originalPrice, type, value) == null) {
      throw const VendorDealsException(
        'Use a valid positive discount with at most two decimal places.',
      );
    }
    if (!end.isAfter(start) || !end.isAfter(DateTime.now())) {
      throw const VendorDealsException(
        'End must be after start and must be in the future.',
      );
    }
    return {
      if (creating) 'productId': dealId(target.productId),
      if (creating && target.offerId != null)
        'productOfferId': dealId(target.offerId),
      'discountType': type,
      'discountValue': double.parse(value.trim()),
      'startAt': start.toUtc().toIso8601String(),
      'endAt': end.toUtc().toIso8601String(),
      'status': status,
    };
  }

  Future<VendorDeal> save(Map<String, dynamic> fields, {String? id}) async {
    try {
      final data = await _request(
        id == null ? '/api/deals' : '/api/deals/${dealId(id)}',
        method: id == null ? 'POST' : 'PATCH',
        body: fields,
      );
      if (data is! Map || data['deal'] is! Map) {
        throw const FormatException('Invalid Deal acknowledgement.');
      }
      return VendorDeal.fromJson(Map<String, dynamic>.from(data['deal']));
    } on VendorDealsException {
      rethrow;
    } catch (_) {
      throw const VendorDealsException(
        'Could not confirm the save. Return to your Deals and refresh before retrying to avoid a duplicate submission.',
      );
    }
  }

  Future<void> pause(String id) async {
    await _request(
      '/api/deals/${dealId(id)}',
      method: 'PATCH',
      body: {'action': 'pause'},
    );
  }
}
