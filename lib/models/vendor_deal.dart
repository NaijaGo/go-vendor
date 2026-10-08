class VendorDeal {
  const VendorDeal({
    required this.id,
    required this.productId,
    this.offerId,
    required this.vendorId,
    required this.discountType,
    required this.discountValue,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.featured,
    required this.reason,
  });
  final String id, productId, vendorId, discountType, status, reason;
  final String? offerId;
  final double discountValue;
  final DateTime? startAt, endAt;
  final bool featured;
  bool get canEdit => ['draft', 'rejected', 'paused'].contains(status);
  bool get canPause => ['approved', 'pending'].contains(status);
  factory VendorDeal.fromJson(Map<String, dynamic> data) {
    final value = double.tryParse('${data['discountValue']}');
    if (value == null ||
        !value.isFinite ||
        value <= 0 ||
        !['percentage', 'fixed'].contains(data['discountType']) ||
        ![
          'draft',
          'pending',
          'approved',
          'rejected',
          'paused',
        ].contains(data['status'])) {
      throw const FormatException('Invalid Deal response.');
    }
    return VendorDeal(
      id: dealId(data['_id']),
      productId: dealId(data['productId']),
      offerId: data['productOfferId'] == null
          ? null
          : dealId(data['productOfferId']),
      vendorId: dealId(data['vendorId']),
      discountType: data['discountType'],
      discountValue: value,
      startAt: DateTime.tryParse('${data['startAt']}')?.toLocal(),
      endAt: DateTime.tryParse('${data['endAt']}')?.toLocal(),
      status: data['status'],
      featured: data['featured'] == true,
      reason: data['moderationReason']?.toString() ?? '',
    );
  }
}

String dealId(dynamic value) {
  final id = value is Map ? value['_id'] : value;
  if (id is! String || !RegExp(r'^[a-fA-F0-9]{24}$').hasMatch(id)) {
    throw const FormatException('Invalid product or Deal identity.');
  }
  return id;
}

class DealTarget {
  const DealTarget({
    required this.productId,
    this.offerId,
    required this.name,
    required this.imageUrl,
    required this.originalPrice,
    required this.existingPrice,
  });
  final String productId, name;
  final String? offerId, imageUrl;
  final double originalPrice, existingPrice;
  String get key => '$productId:${offerId ?? 'aggregate'}';
  static List<DealTarget> fromProduct(
    Map<String, dynamic> product,
    String vendorId,
  ) {
    if (product['isActive'] != true ||
        product['productStatus'] != 'active' ||
        product['moderationStatus'] != 'approved' ||
        (product['variants'] is List &&
            (product['variants'] as List).isNotEmpty) ||
        (product['sizeData'] is Map &&
            (product['sizeData'] as Map)['type'] != null))
      return [];
    final offers = (product['offers'] as List? ?? []).whereType<Map>().toList();
    final relevant = offers
        .where((offer) => ['active', 'out_of_stock'].contains(offer['status']))
        .toList();
    final rows = relevant.isNotEmpty
        ? relevant
              .where(
                (offer) =>
                    offer['status'] == 'active' &&
                    offer['sellerType'] == 'vendor' &&
                    dealId(offer['sellerId']) == vendorId &&
                    !(offer['variants'] is List &&
                        (offer['variants'] as List).isNotEmpty),
              )
              .toList()
        : product['sellerType'] == 'vendor' &&
              dealId(product['sellerId'] ?? product['vendor']) == vendorId
        ? [product]
        : <Map>[];
    return rows.map((row) {
      final price = double.tryParse('${row['price']}');
      if (price == null || !price.isFinite || price < 0)
        throw const FormatException('Invalid product price.');
      final images = product['imageUrls'] as List? ?? [];
      return DealTarget(
        productId: dealId(product['_id']),
        offerId: relevant.isNotEmpty ? dealId(row['_id']) : null,
        name: product['name']?.toString() ?? 'Product',
        imageUrl: images.isEmpty ? null : images.first.toString(),
        originalPrice: price,
        existingPrice:
            double.tryParse('${row['discountPrice'] ?? row['price']}') ?? price,
      );
    }).toList();
  }
}

class DealPreview {
  const DealPreview(this.original, this.finalPrice);
  final double original, finalPrice;
  double get savings => ((original - finalPrice) * 100).round() / 100;
  static DealPreview? calculate(double price, String type, String input) {
    final value = double.tryParse(input.trim());
    if (!price.isFinite ||
        price < 0 ||
        value == null ||
        !value.isFinite ||
        value <= 0 ||
        (type == 'percentage'
            ? value > 100
            : type != 'fixed' || value > 1e9 || value > price) ||
        (value * 100).round() / 100 != value ||
        !(price * 100).isFinite) {
      return null;
    }
    final raw = type == 'percentage'
        ? price * (1 - value / 100)
        : price - value;
    return DealPreview(
      price,
      ((raw + 2.220446049250313e-16) * 100).round() / 100,
    );
  }
}
