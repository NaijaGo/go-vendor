import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants.dart';

class PickupOrdersScreen extends StatefulWidget {
  const PickupOrdersScreen({super.key});
  @override
  State<PickupOrdersScreen> createState() => _PickupOrdersScreenState();
}

class _PickupOrdersScreenState extends State<PickupOrdersScreen> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> orders = [];
  Future<Map<String, String>> headers() async {
    final p = await SharedPreferences.getInstance();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${p.getString('jwt_token') ?? ''}',
    };
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(
        Uri.parse('$baseUrl/api/pickup/vendor/orders'),
        headers: await headers(),
      );
      if (r.statusCode != 200) throw Exception();
      if (mounted)
        setState(() {
          orders = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
          loading = false;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'Unable to connect. Check your internet and try again.';
        });
    }
  }

  Future<void> status(String id, String value) async {
    final r = await http.patch(
      Uri.parse('$baseUrl/api/pickup/vendor/orders/$id/status'),
      headers: await headers(),
      body: jsonEncode({'status': value}),
    );
    if (!mounted) return;
    final d = jsonDecode(r.body);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${d['message']}')));
    if (r.statusCode == 200) load();
  }

  Future<void> verify(String id) async {
    final code = TextEditingController();
    String? token;
    final submit = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Verify customer pickup',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 210,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: MobileScanner(
                  onDetect: (capture) {
                    final raw = capture.barcodes.first.rawValue;
                    if (raw == null) return;
                    try {
                      token = jsonDecode(raw)['token'];
                    } catch (_) {
                      token = raw;
                    }
                    Navigator.pop(context, true);
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Or enter pickup code',
                hintText: 'NG-48291',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Verify code'),
              ),
            ),
          ],
        ),
      ),
    );
    if (submit != true) {
      code.dispose();
      return;
    }
    final r = await http.post(
      Uri.parse('$baseUrl/api/pickup/vendor/orders/$id/verify'),
      headers: await headers(),
      body: jsonEncode({'pickupCode': code.text.trim(), 'qrToken': token}),
    );
    code.dispose();
    if (!mounted) return;
    final d = jsonDecode(r.body);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${d['message']}')));
    if (r.statusCode == 200) load();
  }

  Future<void> configurePickup() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/pickup/vendor/settings'),
      headers: await headers(),
    );
    if (response.statusCode != 200 || !mounted) return;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final settings = data['pickupSettings'] as Map<String, dynamic>? ?? {};
    var enabled = data['pickupEnabled'] == true;
    final shop = TextEditingController(
      text: '${settings['shopName'] ?? data['businessName'] ?? ''}',
    );
    final phone = TextEditingController(
      text: '${settings['phoneNumber'] ?? data['phoneNumber'] ?? ''}',
    );
    final instructions = TextEditingController(
      text: '${settings['instructions'] ?? ''}',
    );
    final preparation = TextEditingController(
      text: '${settings['estimatedPreparationMinutes'] ?? 30}',
    );
    final capacity = TextEditingController(
      text: '${settings['maximumConcurrentOrders'] ?? 20}',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Pickup settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: (value) => setLocalState(() => enabled = value),
                  title: const Text('Accept customer pickup'),
                  subtitle: const Text(
                    'Your complete store address and map pin are required.',
                  ),
                ),
                TextField(
                  controller: shop,
                  decoration: const InputDecoration(
                    labelText: 'Pickup shop name',
                  ),
                ),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Pickup phone'),
                ),
                TextField(
                  controller: preparation,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Preparation time (minutes)',
                  ),
                ),
                TextField(
                  controller: capacity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum active pickup orders',
                  ),
                ),
                TextField(
                  controller: instructions,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Pickup instructions',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final result = await http.put(
        Uri.parse('$baseUrl/api/pickup/vendor/settings'),
        headers: await headers(),
        body: jsonEncode({
          'pickupEnabled': enabled,
          'pickupSettings': {
            'shopName': shop.text.trim(),
            'phoneNumber': phone.text.trim(),
            'instructions': instructions.text.trim(),
            'estimatedPreparationMinutes': int.tryParse(preparation.text),
            'maximumConcurrentOrders': int.tryParse(capacity.text),
            'hours': settings['hours'] ?? [],
          },
        }),
      );
      if (mounted) {
        final body = jsonDecode(result.body);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${body['message']}')));
      }
    }
    shop.dispose();
    phone.dispose();
    instructions.dispose();
    preparation.dispose();
    capacity.dispose();
  }

  Widget action(Map<String, dynamic> o) {
    final s = '${o['shipmentStatus']}', id = '${o['_id']}';
    if (s == 'processing')
      return FilledButton(
        onPressed: () => status(id, 'accepted'),
        child: const Text('Accept Order'),
      );
    if (s == 'accepted')
      return FilledButton(
        onPressed: () => status(id, 'preparing'),
        child: const Text('Start Preparing'),
      );
    if (s == 'preparing')
      return FilledButton(
        onPressed: () => status(id, 'ready_for_customer_pickup'),
        child: const Text('Ready for Pickup'),
      );
    if (s == 'ready_for_customer_pickup')
      return FilledButton.icon(
        onPressed: () => verify(id),
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Verify Pickup'),
      );
    return const Chip(label: Text('Pickup Verified'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Pickup Orders'),
      actions: [
        IconButton(
          tooltip: 'Pickup settings',
          onPressed: configurePickup,
          icon: const Icon(Icons.settings_outlined),
        ),
        IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: load,
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? ListView(
              children: [
                const SizedBox(height: 150),
                Center(child: Text(error!)),
              ],
            )
          : orders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 150),
                Icon(Icons.storefront_outlined, size: 60),
                Center(child: Text('No pickup orders yet')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final o = orders[i], items = o['items'] as List? ?? [];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${'${o['_id']}'.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${items.length} product line${items.length == 1 ? '' : 's'} • ${'${o['shipmentStatus']}'.replaceAll('_', ' ')}',
                        ),
                        const SizedBox(height: 12),
                        action(o),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}
