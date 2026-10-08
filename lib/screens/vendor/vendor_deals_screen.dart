import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/vendor_deal.dart';
import '../../services/vendor_deals_service.dart';
import '../../widgets/vendor_ui.dart';
import 'vendor_deal_form_screen.dart';

class VendorDealsScreen extends StatefulWidget {
  const VendorDealsScreen({super.key, this.service});
  final VendorDealsService? service;
  @override
  State<VendorDealsScreen> createState() => _VendorDealsScreenState();
}

class _VendorDealsScreenState extends State<VendorDealsScreen> {
  late final VendorDealsService _service;
  List<VendorDeal> _deals = [];
  final Map<String, Map<String, dynamic>?> _products = {};
  bool _loading = true, _loadingMore = false, _hasMore = false;
  bool _failureWasMore = false;
  String? _filter, _error, _changing;
  int _page = 0, _generation = 0;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? VendorDealsService();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_changing != null || (more && (_loading || _loadingMore || !_hasMore)))
      return;
    final generation = more ? _generation : ++_generation;
    final next = more ? _page + 1 : 1;
    if (!more) _service.clearProducts();
    setState(() {
      _loading = !more;
      _loadingMore = more;
      _error = null;
      _failureWasMore = more;
    });
    try {
      final result = await _service.mine(page: next, status: _filter);
      final ids = result.deals.map((deal) => deal.productId).toSet().toList();
      final products = <String, Map<String, dynamic>?>{};
      // Bound product-detail requests; cache shared products within this refresh.
      for (var i = 0; i < ids.length; i += 4) {
        if (!mounted || generation != _generation) return;
        await Future.wait(
          ids.skip(i).take(4).map((id) async {
            products[id] = await _service.product(id);
          }),
        );
      }
      if (!mounted || generation != _generation) return;
      final seen = <String>{};
      setState(() {
        _deals = [
          ...(more ? _deals : <VendorDeal>[]),
          ...result.deals,
        ].where((deal) => seen.add(deal.id)).toList();
        if (!more) _products.clear();
        _products.addAll(products);
        _page = result.page;
        _hasMore = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(
          () => _error = error is VendorDealsException
              ? error.message
              : 'Could not load your Deals. Try refreshing.',
        );
    } finally {
      if (mounted && generation == _generation)
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
    }
  }

  Future<void> _edit([VendorDeal? deal]) async {
    _service.clearProducts();
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VendorDealFormScreen(service: _service, deal: deal),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _pause(VendorDeal deal) async {
    if (_changing != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pause this Deal?'),
        content: const Text(
          'Customers will no longer receive this timed Deal. You can edit and resubmit it for approval. Only Admin can restore an approved Deal directly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pause Deal'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changing = deal.id);
    var success = false;
    try {
      await _service.pause(deal.id);
      success = true;
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _changing = null);
    }
    if (success && mounted) await _load();
  }

  DealTarget? _target(VendorDeal deal) {
    final product = _products[deal.productId];
    if (product == null) return null;
    try {
      return DealTarget.fromProduct(
        product,
        deal.vendorId,
      ).where((target) => target.offerId == deal.offerId).firstOrNull;
    } catch (_) {
      return null;
    }
  }

  Widget _card(VendorDeal deal) {
    final product = _products[deal.productId];
    final target = _target(deal);
    final preview = target == null
        ? null
        : DealPreview.calculate(
            target.originalPrice,
            deal.discountType,
            '${deal.discountValue}',
          );
    final images = product?['imageUrls'] as List? ?? [];
    final color = deal.status == 'approved'
        ? VendorUi.success
        : deal.status == 'rejected'
        ? VendorUi.danger
        : VendorUi.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: VendorUi.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: images.isEmpty
                      ? const Icon(
                          Icons.shopping_bag_outlined,
                          color: VendorUi.textMuted,
                        )
                      : CachedNetworkImage(
                          imageUrl: images.first.toString(),
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              const Icon(Icons.image_not_supported_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product?['name']?.toString() ??
                          'Product ${deal.productId}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      deal.offerId == null
                          ? 'Product stock'
                          : 'Offer ${deal.offerId!.substring(18)}',
                      style: const TextStyle(color: VendorUi.textMuted),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            '${deal.status[0].toUpperCase()}${deal.status.substring(1)}',
                            style: TextStyle(color: color),
                          ),
                        ),
                        if (deal.featured)
                          const Chip(
                            avatar: Icon(Icons.star, size: 16),
                            label: Text('Featured'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            deal.discountType == 'percentage'
                ? '${deal.discountValue}% off'
                : '${vendorDealMoney(deal.discountValue)} off',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Original price: ${target == null ? 'Unavailable' : vendorDealMoney(target.originalPrice)}',
          ),
          Text(
            'Deal price preview: ${preview == null ? 'Unavailable' : vendorDealMoney(preview.finalPrice)}',
          ),
          const Text(
            'Preview uses current product pricing. Backend pricing is authoritative.',
            style: TextStyle(fontSize: 12, color: VendorUi.textMuted),
          ),
          if (preview != null && preview.finalPrice >= target!.existingPrice)
            const Text(
              'An existing discount is equal or better; discounts do not stack.',
              style: TextStyle(color: VendorUi.warning),
            ),
          const SizedBox(height: 8),
          Text('Starts: ${vendorDealDate(deal.startAt)}'),
          Text('Ends: ${vendorDealDate(deal.endAt)}'),
          if (deal.endAt != null && !deal.endAt!.isAfter(DateTime.now()))
            const Text(
              'Time window ended',
              style: TextStyle(color: VendorUi.textMuted),
            ),
          if (deal.reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Admin feedback: ${deal.reason}'),
            ),
          if (deal.canEdit || deal.canPause)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (deal.canEdit)
                    OutlinedButton.icon(
                      onPressed: _changing == null ? () => _edit(deal) : null,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit / resubmit'),
                    ),
                  if (deal.canPause)
                    OutlinedButton.icon(
                      onPressed: _changing == null ? () => _pause(deal) : null,
                      icon: const Icon(Icons.pause_circle_outline),
                      label: Text(_changing == deal.id ? 'Pausing…' : 'Pause'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: VendorUi.theme,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('NaijaGo Deals'),
        actions: [
          IconButton(
            tooltip: 'Refresh Deals',
            onPressed: _loading || _changing != null ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _changing == null ? () => _edit() : null,
        icon: const Icon(Icons.add),
        label: const Text('Create Deal'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Text(
              'Manage your timed offers',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Submitted Deals require Admin approval. Featured placement is controlled by Admin. Dates are shown in your device local timezone.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _filter ?? 'all',
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['all', 'draft', 'pending', 'approved', 'rejected', 'paused']
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(
                        status == 'all'
                            ? 'All Deals'
                            : '${status[0].toUpperCase()}${status.substring(1)}',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _changing != null
                  ? null
                  : (status) {
                      setState(() {
                        _filter = status == 'all' ? null : status;
                        _deals = [];
                        _hasMore = false;
                      });
                      _load();
                    },
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: VendorUi.panelDecoration(),
                child: Column(
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: () => _load(more: _failureWasMore),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            if (!_loading && _error == null && _deals.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: VendorUi.panelDecoration(),
                child: const Text(
                  'No Deals here yet. Create a timed offer for one of your products.',
                ),
              ),
            ..._deals.map(_card),
            if (_loadingMore) const Center(child: CircularProgressIndicator()),
            if (_hasMore && !_loading && !_loadingMore)
              OutlinedButton(
                onPressed: () => _load(more: true),
                child: const Text('Load more Deals'),
              ),
          ],
        ),
      ),
    ),
  );
}
