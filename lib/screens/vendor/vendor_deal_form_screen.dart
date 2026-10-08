import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/vendor_deal.dart';
import '../../services/vendor_deals_service.dart';
import '../../widgets/vendor_ui.dart';

String vendorDealMoney(double value) => NumberFormat.currency(
  locale: 'en_NG',
  symbol: '₦',
  decimalDigits: 2,
).format(value);
String vendorDealDate(DateTime? value) => value == null
    ? 'Date unavailable'
    : DateFormat('d MMM yyyy, h:mm a').format(value.toLocal());

class VendorDealFormScreen extends StatefulWidget {
  const VendorDealFormScreen({super.key, required this.service, this.deal});
  final VendorDealsService service;
  final VendorDeal? deal;
  @override
  State<VendorDealFormScreen> createState() => _VendorDealFormScreenState();
}

class _VendorDealFormScreenState extends State<VendorDealFormScreen> {
  final _form = GlobalKey<FormState>();
  final _value = TextEditingController();
  List<Map<String, dynamic>> _products = [];
  List<DealTarget> _targets = [];
  DealTarget? _target;
  String? _productId, _vendorId, _error, _targetError;
  String _type = 'percentage';
  DateTime? _start, _end;
  bool _loading = true,
      _loadingProducts = false,
      _moreProducts = false,
      _selecting = false,
      _saving = false;
  int _productPage = 0, _selectionGeneration = 0;
  @override
  void initState() {
    super.initState();
    _type = widget.deal?.discountType ?? 'percentage';
    _value.text = widget.deal?.discountValue.toString() ?? '';
    _start = widget.deal?.startAt;
    _end = widget.deal?.endAt;
    _initialize();
  }

  @override
  void dispose() {
    _selectionGeneration++;
    _value.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _vendorId = await widget.service.vendorId();
      if (!mounted) return;
      if (widget.deal != null) {
        if (widget.deal!.vendorId != _vendorId || !widget.deal!.canEdit) {
          throw const VendorDealsException(
            'This Deal cannot be edited. Refresh your Deals.',
          );
        }
        await _selectProduct(widget.deal!.productId, editing: true);
      } else {
        _products = [];
        _productPage = 0;
        _moreProducts = false;
        _productId = null;
        _target = null;
        _targets = [];
        await _loadProducts();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProducts() async {
    if (_loadingProducts) return;
    setState(() {
      _loadingProducts = true;
      _error = null;
    });
    try {
      final next = _productPage + 1;
      final rows = await widget.service.ownedProducts(next);
      if (!mounted) return;
      final ids = <String>{};
      setState(() {
        _products = [
          ..._products,
          ...rows,
        ].where((row) => ids.add(dealId(row['_id']))).toList();
        _productPage = next;
        _moreProducts = rows.length == 50;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  Future<void> _selectProduct(String id, {bool editing = false}) async {
    final generation = ++_selectionGeneration;
    if (!mounted) return;
    setState(() {
      _productId = id;
      _selecting = true;
      _target = null;
      _targets = [];
      _targetError = null;
    });
    try {
      final product = await widget.service.product(id);
      if (product == null)
        throw const VendorDealsException(
          'Could not load current product information. Try again.',
        );
      final targets = DealTarget.fromProduct(product, _vendorId!);
      if (targets.isEmpty)
        throw const VendorDealsException(
          'This product has no eligible active offer. Deals require approved products; variant/size Deals are not supported.',
        );
      final selected = editing
          ? targets
                .where((target) => target.offerId == widget.deal!.offerId)
                .firstOrNull
          : targets.length == 1
          ? targets.single
          : null;
      if (editing && selected == null)
        throw const VendorDealsException(
          'The original product offer is no longer eligible. The Deal target cannot be changed.',
        );
      if (mounted && generation == _selectionGeneration)
        setState(() {
          _targets = targets;
          _target = selected;
        });
    } catch (error) {
      if (mounted && generation == _selectionGeneration)
        setState(() => _targetError = error.toString());
    } finally {
      if (mounted && generation == _selectionGeneration)
        setState(() => _selecting = false);
    }
  }

  Future<void> _pickDate(bool start) async {
    final current = (start ? _start : _end) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (value.year != date.year ||
        value.month != date.month ||
        value.day != date.day ||
        value.hour != time.hour ||
        value.minute != time.minute) {
      setState(
        () => _error = 'That time does not exist in your local timezone. Choose another time.',
      );
      return;
    }
    setState(() {
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
  }

  Future<void> _save(String status) async {
    if (_saving || !_form.currentState!.validate()) return;
    if (_target == null || _start == null || _end == null) {
      setState(
        () => _error = 'Choose an eligible product/offer and both dates.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = widget.service.fields(
        _target!,
        _type,
        _value.text,
        _start!,
        _end!,
        status,
        creating: widget.deal == null,
      );
      await widget.service.save(fields, id: widget.deal?.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'draft'
                ? 'Deal draft saved.'
                : 'Deal submitted for Admin approval.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _target == null
        ? null
        : DealPreview.calculate(_target!.originalPrice, _type, _value.text);
    final offset = DateTime.now().timeZoneOffset;
    final timezone =
        '${offset.isNegative ? '-' : '+'}${offset.inHours.abs().toString().padLeft(2, '0')}:${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: !_saving,
      child: Theme(
        data: VendorUi.theme,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.deal == null ? 'Create Deal' : 'Edit Deal'),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _form,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Timed product offer',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Submit for Admin review. Editing a paused or rejected Deal clears its previous approval. Variants and sizes are not supported.',
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(color: VendorUi.danger),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  widget.service.clearProducts();
                                  _initialize();
                                },
                          child: const Text('Reload products'),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.deal == null) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _productId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Your product',
                          ),
                          items: _products
                              .map(
                                (row) => DropdownMenuItem(
                                  value: dealId(row['_id']),
                                  child: Text(
                                    row['name']?.toString() ?? 'Product',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (id) {
                                  if (id != null) _selectProduct(id);
                                },
                        ),
                        if (_products.isEmpty && !_loadingProducts)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'No products found. Add a product before creating a Deal.',
                            ),
                          ),
                        if (_loadingProducts) const LinearProgressIndicator(),
                        if (_moreProducts)
                          TextButton(
                            onPressed: _loadingProducts || _saving
                                ? null
                                : _loadProducts,
                            child: const Text('Load more products'),
                          ),
                      ] else
                        Text(
                          _target?.name ?? 'Product ${widget.deal!.productId}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      if (_selecting) const LinearProgressIndicator(),
                      if (_targetError != null) ...[
                        Text(
                          _targetError!,
                          style: const TextStyle(color: VendorUi.danger),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  widget.service.clearProducts();
                                  _selectProduct(
                                    _productId!,
                                    editing: widget.deal != null,
                                  );
                                },
                          child: const Text('Retry product'),
                        ),
                      ],
                      if (_targets.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('$_productId-${_target?.key}'),
                            initialValue: _target?.key,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Product offer',
                            ),
                            items: _targets
                                .map(
                                  (target) => DropdownMenuItem(
                                    value: target.key,
                                    child: Text(
                                      '${target.offerId == null ? 'Product stock' : 'Offer ${target.offerId!.substring(18)}'} · ${vendorDealMoney(target.originalPrice)}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving || widget.deal != null
                                ? null
                                : (key) => setState(
                                    () => _target = _targets.firstWhere(
                                      (target) => target.key == key,
                                    ),
                                  ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration: const InputDecoration(
                          labelText: 'Discount type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'percentage',
                            child: Text('Percentage (%)'),
                          ),
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Fixed amount (₦)'),
                          ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _type = value!),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _value,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _type == 'percentage'
                              ? 'Discount percentage'
                              : 'Discount amount (₦)',
                          helperText:
                              'Positive value, at most two decimal places',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (_) => _target == null
                            ? 'Choose an eligible offer first.'
                            : DealPreview.calculate(
                                    _target!.originalPrice,
                                    _type,
                                    _value.text,
                                  ) ==
                                  null
                            ? (_type == 'percentage'
                                  ? 'Enter a percentage above 0 and up to 100.'
                                  : 'Enter a positive discount no greater than the product price or ₦1 billion.')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: VendorUi.panelDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Price preview · not a checkout quote',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'Original: ${_target == null ? 'Choose a product' : vendorDealMoney(_target!.originalPrice)}',
                            ),
                            Text(
                              'Deal price: ${preview == null ? 'Enter a valid discount' : vendorDealMoney(preview.finalPrice)}',
                            ),
                            if (preview != null)
                              Text(
                                'Savings: ${vendorDealMoney(preview.savings)}',
                              ),
                            const Text(
                              'Backend validation and approval determine the price. Discounts do not stack.',
                            ),
                            if (preview != null &&
                                preview.finalPrice >= _target!.existingPrice)
                              const Text(
                                'An existing product discount is equal or better. This timed Deal will not be advertised at that price.',
                                style: TextStyle(color: VendorUi.warning),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Dates use your device local timezone (UTC$timezone). The same instants are sent to the server in UTC.',
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickDate(true),
                        icon: const Icon(Icons.event),
                        label: Text(
                          _start == null
                              ? 'Choose start date and time'
                              : 'Starts: ${vendorDealDate(_start)}',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _pickDate(false),
                        icon: const Icon(Icons.event_available),
                        label: Text(
                          _end == null
                              ? 'Choose end date and time'
                              : 'Ends: ${vendorDealDate(_end)}',
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _saving || _target == null
                            ? null
                            : () => _save('pending'),
                        child: Text(
                          _saving ? 'Saving…' : 'Submit for approval',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _saving || _target == null
                            ? null
                            : () => _save('draft'),
                        child: const Text('Save draft'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
