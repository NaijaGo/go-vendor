// Dependency-free Dart runtime checks. Does not replace Flutter build verification.
import '../lib/models/vendor_deal.dart';

void main() {
  var passed = 0;
  void check(String name, void Function() body) {
    body();
    passed++;
    print('PASS: ' + name);
  }

  void expect(bool value) {
    if (!value) throw StateError('Expectation failed');
  }

  void rejects(void Function() work) {
    var failed = false;
    try {
      work();
    } catch (_) {
      failed = true;
    }
    expect(failed);
  }

  const vendor = '507f1f77bcf86cd799439011',
      product = '507f1f77bcf86cd799439012',
      offer = '507f1f77bcf86cd799439013',
      other = '507f1f77bcf86cd799439014';
  final row = <String, dynamic>{
    '_id': offer,
    'productId': product,
    'vendorId': vendor,
    'discountType': 'percentage',
    'discountValue': 30,
    'status': 'pending',
    'startAt': '2026-10-08T10:00:00Z',
    'endAt': '2026-10-09T10:00:00Z',
  };
  check('backend managed Deal parsing', () {
    final d = VendorDeal.fromJson(row);
    expect(
      d.id == offer &&
          d.vendorId == vendor &&
          d.discountValue == 30 &&
          d.startAt != null,
    );
  });
  check('invalid identifiers fail closed', () {
    for (final key in ['_id', 'productId', 'vendorId'])
      rejects(() => VendorDeal.fromJson({...row, key: 'bad'}));
  });
  check('invalid discount and status fail closed', () {
    for (final v in [0, -1, double.nan, double.infinity])
      rejects(() => VendorDeal.fromJson({...row, 'discountValue': v}));
    rejects(() => VendorDeal.fromJson({...row, 'status': 'live'}));
  });
  check('missing dates remain unavailable', () {
    final d = VendorDeal.fromJson({...row, 'startAt': null, 'endAt': 'bad'});
    expect(d.startAt == null && d.endAt == null);
  });
  check('edit and pause capabilities match backend statuses', () {
    for (final s in ['draft', 'pending', 'approved', 'rejected', 'paused']) {
      final d = VendorDeal.fromJson({...row, 'status': s});
      expect(d.canEdit == ['draft', 'rejected', 'paused'].contains(s));
      expect(d.canPause == ['approved', 'pending'].contains(s));
    }
  });
  check('percentage preview', () {
    final p = DealPreview.calculate(10000, 'percentage', '30')!;
    expect(p.finalPrice == 7000 && p.savings == 3000);
  });
  check('fixed preview', () {
    final p = DealPreview.calculate(10000, 'fixed', '1500')!;
    expect(p.finalPrice == 8500 && p.savings == 1500);
  });
  check('invalid previews rejected', () {
    for (final v in ['0', '-1', 'NaN', 'Infinity', '100.001', '101'])
      expect(DealPreview.calculate(10000, 'percentage', v) == null);
    expect(DealPreview.calculate(10, 'fixed', '11') == null);
    expect(DealPreview.calculate(10, 'bogo', '1') == null);
  });
  check('zero-price boundary and two-decimal preview', () {
    expect(DealPreview.calculate(10, 'fixed', '10')!.finalPrice == 0);
    expect(
      DealPreview.calculate(100, 'percentage', '12.34')!.finalPrice == 87.66,
    );
  });
  final base = <String, dynamic>{
    '_id': product,
    'name': 'Fixture',
    'isActive': true,
    'productStatus': 'active',
    'moderationStatus': 'approved',
    'sellerType': 'vendor',
    'sellerId': vendor,
    'price': 10000,
    'imageUrls': [],
  };
  check('legacy product ownership enforced', () {
    expect(DealTarget.fromProduct(base, vendor).length == 1);
    expect(DealTarget.fromProduct(base, other).isEmpty);
  });
  check('variant and size reservations/deals fail closed', () {
    expect(
      DealTarget.fromProduct({
        ...base,
        'variants': [{}],
      }, vendor).isEmpty,
    );
    expect(
      DealTarget.fromProduct({
        ...base,
        'sizeData': {'type': 'clothing'},
      }, vendor).isEmpty,
    );
  });
  check('selected offers enforce ownership and exclude inactive offers', () {
    final owned = {
      '_id': offer,
      'sellerType': 'vendor',
      'sellerId': vendor,
      'status': 'active',
      'price': 9000,
    };
    final list = DealTarget.fromProduct({
      ...base,
      'offers': [
        owned,
        {...owned, '_id': other, 'sellerId': other},
      ],
    }, vendor);
    expect(
      list.length == 1 &&
          list.single.offerId == offer &&
          list.single.originalPrice == 9000,
    );
    expect(
      DealTarget.fromProduct({
        ...base,
        'offers': [
          {...owned, 'status': 'out_of_stock'},
        ],
      }, vendor).isEmpty,
    );
  });
  print('RESULT: ' + passed.toString() + ' passed, 0 failed');
}
