import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:naijagovendorsapp/models/vendor_deal.dart';
import 'package:naijagovendorsapp/services/vendor_deals_service.dart';

const product = '507f1f77bcf86cd799439011',
    vendor = '507f1f77bcf86cd799439012',
    deal = '507f1f77bcf86cd799439013';
Map<String, dynamic> record() => {
  '_id': deal,
  'productId': product,
  'vendorId': vendor,
  'discountType': 'percentage',
  'discountValue': 30,
  'status': 'pending',
  'startAt': '2026-10-08T00:00:00Z',
  'endAt': '2026-10-09T00:00:00Z',
};
void main() {
  test('mine matches backend pagination and status query', () async {
    final service = VendorDealsService(
      get: (path) async {
        expect(path, '/api/deals/mine?page=2&limit=20&status=pending');
        return http.Response(
          jsonEncode({
            'deals': [record()],
            'page': 2,
            'total': 21,
            'limit': 20,
            'hasMore': false,
          }),
          200,
        );
      },
    );
    final page = await service.mine(page: 2, status: 'pending');
    expect(page.deals.single.id, deal);
    expect(page.page, 2);
    expect(page.hasMore, false);
  });
  test('successful empty page is not an error', () async {
    final service = VendorDealsService(
      get: (_) async => http.Response(
        jsonEncode({'deals': [], 'page': 1, 'hasMore': false}),
        200,
      ),
    );
    expect((await service.mine()).deals, isEmpty);
  });
  for (final status in [401, 403, 404, 500]) {
    test('HTTP ' + status.toString() + ' produces safe error', () async {
      final service = VendorDealsService(
        get: (_) async => http.Response('private server exception', status),
      );
      await expectLater(
        service.mine(),
        throwsA(
          isA<VendorDealsException>().having(
            (e) => e.message,
            'message',
            isNot(contains('private server exception')),
          ),
        ),
      );
    });
  }
  test('create fields contain no vendor identity or submitted price', () {
    final service = VendorDealsService();
    final target = DealTarget(
      productId: product,
      name: 'Fixture',
      imageUrl: null,
      originalPrice: 10000,
      existingPrice: 10000,
    );
    final start = DateTime.now().add(const Duration(days: 1)),
        end = start.add(const Duration(days: 1));
    final fields = service.fields(
      target,
      'percentage',
      '30',
      start,
      end,
      'pending',
      creating: true,
    );
    expect(fields['productId'], product);
    expect(fields['discountValue'], 30);
    expect(fields.containsKey('vendorId'), false);
    expect(fields.containsKey('price'), false);
    expect(fields['startAt'], start.toUtc().toIso8601String());
    expect(
      () => service.fields(target, 'percentage', '101', start, end, 'pending'),
      throwsA(isA<VendorDealsException>()),
    );
    expect(
      () => service.fields(target, 'fixed', '10001', start, end, 'pending'),
      throwsA(isA<VendorDealsException>()),
    );
    expect(
      () => service.fields(target, 'fixed', '1', end, start, 'pending'),
      throwsA(isA<VendorDealsException>()),
    );
  });
  test('valid save acknowledgement parses stored backend Deal', () async {
    final service = VendorDealsService(
      post: (path, body) async {
        expect(path, '/api/deals');
        return http.Response(jsonEncode({'deal': record()}), 201);
      },
    );
    expect((await service.save({})).id, deal);
  });
  for (final body in [
    '{}',
    '[]',
    jsonEncode({
      'deal': {'_id': 'bad'},
    }),
  ]) {
    test(
      'malformed save acknowledgement requires refresh instead of exposing raw exceptions: ' +
          body,
      () async {
        final service = VendorDealsService(
          post: (_, __) async => http.Response(body, 201),
        );
        await expectLater(
          service.save({}),
          throwsA(
            isA<VendorDealsException>().having(
              (e) => e.message,
              'message',
              contains('refresh before retrying'),
            ),
          ),
        );
      },
    );
  }
  test('pause uses the established authenticated patch abstraction', () async {
    final service = VendorDealsService(
      patch: (path, body) async {
        expect(path, '/api/deals/' + deal);
        expect(body, {'action': 'pause'});
        return http.Response(
          jsonEncode({
            'deal': {...record(), 'status': 'paused'},
          }),
          200,
        );
      },
    );
    await service.pause(deal);
  });
}
