import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../constants.dart';
import '../../services/socket_service.dart';
import '../vendor/add_product_screen.dart';
import '../vendor/orders_recived_screen.dart.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'vendor_my_products_screen.dart';
import 'vendor_screen.dart';

class VendorAppNavigator extends StatefulWidget {
  final Map<String, dynamic> user;
  final String? syncError;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  const VendorAppNavigator({
    super.key,
    required this.user,
    required this.onRefresh,
    required this.onLogout,
    this.syncError,
  });

  @override
  State<VendorAppNavigator> createState() => _VendorAppNavigatorState();
}

class _VendorAppNavigatorState extends State<VendorAppNavigator> {
  int _selectedIndex = 0;
  late List<dynamic> _notifications;
  final SocketService _socketService = SocketService();

  static const Color _primaryNavy = Color(0xFF102B5C);
  static const Color _surface = Color(0xFFF5F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _danger = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _notifications = _dedupeNotifications(_readNotifications(widget.user));
    _connectVendorNotifications();
  }

  @override
  void didUpdateWidget(covariant VendorAppNavigator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user != widget.user) {
      _notifications = _dedupeNotifications([
        ..._readNotifications(widget.user),
        ..._notifications,
      ]);
      _connectVendorNotifications();
    }
  }

  @override
  void dispose() {
    _socketService.dispose();
    super.dispose();
  }

  bool get _isApprovedVendor =>
      widget.user['isVendor'] == true && _vendorStatus == 'approved';

  String get _vendorStatus => widget.user['vendorStatus']?.toString() ?? 'none';

  List<Widget> get _pages {
    final dashboard = VendorScreen(
      isApprovedVendor: _isApprovedVendor,
      vendorStatus: _vendorStatus,
      rejectionDate: _parseDate(widget.user['vendorRejectionDate']),
      vendorWalletBalance: _parseDouble(widget.user['vendorWalletBalance']),
      appWalletBalance: _parseDouble(widget.user['appWalletBalance']),
      userWalletBalance: _parseDouble(widget.user['userWalletBalance']),
      totalProducts: _parseInt(widget.user['totalProducts']),
      productsSold: _parseInt(widget.user['productsSold']),
      productsUnsold: _parseInt(widget.user['productsUnsold']),
      followersCount: _parseInt(widget.user['followersCount']),
      isPharmacist:
          widget.user['isPharmacist'] == true ||
          widget.user['role']?.toString() == 'pharmacist',
      pharmacistStatus: widget.user['pharmacistStatus']?.toString() ?? 'none',
      notifications: _notifications,
      onRefresh: widget.onRefresh,
    );

    return [
      dashboard,
      _isApprovedVendor ? const VendorMyProductsScreen() : dashboard,
      _isApprovedVendor ? const OrdersRecivedScreen() : dashboard,
      AccountScreen(onLogout: widget.onLogout),
    ];
  }

  String get _title {
    switch (_selectedIndex) {
      case 1:
        return 'Products';
      case 2:
        return 'Orders';
      case 3:
        return 'Account';
      default:
        return _isApprovedVendor ? 'Vendor Dashboard' : 'Vendor Access';
    }
  }

  void _onItemTapped(int index) {
    if (!_isApprovedVendor && (index == 1 || index == 2)) {
      setState(() => _selectedIndex = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete vendor approval to unlock this workspace.'),
        ),
      );
      return;
    }

    setState(() => _selectedIndex = index);
  }

  Future<void> _connectVendorNotifications() async {
    if (!_isApprovedVendor) return;

    await _socketService.connect(baseUrl);
    _socketService.off('vendor_notification');
    _socketService.on('vendor_notification', (payload) {
      if (!mounted) return;

      final data = payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{'message': payload.toString()};
      final message = _socketNotificationMessage(
        data,
        fallback: 'You have a new vendor alert.',
      );

      setState(() {
        _notifications = _dedupeNotifications([
          {
            '_id': DateTime.now().microsecondsSinceEpoch.toString(),
            'type': data['data']?['type'] ?? 'new_order',
            'message': message,
            'read': false,
            'createdAt': DateTime.now().toIso8601String(),
          },
          ..._notifications,
        ]);
      });

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(data['title']?.toString() ?? 'New vendor order'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => _onItemTapped(2),
          ),
        ),
      );
      unawaited(_playVendorOrderAlert());
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 700), () {
          if (mounted) return widget.onRefresh();
        }),
      );
    });
  }

  Future<void> _playVendorOrderAlert() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.vibrate();
    } catch (_) {
      // Some desktop/web targets do not support haptics or alert sounds.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            NotificationsScreen(notifications: _notifications),
      ),
    );
    await widget.onRefresh();
  }

  Future<void> _openAddProduct() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const AddProductScreen()));
    await widget.onRefresh();
  }

  PreferredSizeWidget _buildAppBar() {
    final unreadCount = _notifications.where((n) => n['read'] == false).length;

    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 16,
      title: Text(
        _title,
        style: const TextStyle(
          color: _text,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border.withValues(alpha: 0.7)),
      ),
      actions: [
        if (_isApprovedVendor)
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: _openNotifications,
                icon: const Icon(Icons.notifications_none_rounded),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: widget.onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: Colors.white,
          selectedItemColor: _primaryNavy,
          unselectedItemColor: _muted,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Ionicons.storefront_outline),
              activeIcon: Icon(Ionicons.storefront),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Ionicons.cube_outline),
              activeIcon: Icon(Ionicons.cube),
              label: 'Products',
            ),
            BottomNavigationBarItem(
              icon: Icon(Ionicons.receipt_outline),
              activeIcon: Icon(Ionicons.receipt),
              label: 'Orders',
            ),
            BottomNavigationBarItem(
              icon: Icon(Ionicons.person_outline),
              activeIcon: Icon(Ionicons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: _surface,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (widget.syncError != null)
            MaterialBanner(
              content: Text(widget.syncError!),
              actions: [
                TextButton(
                  onPressed: widget.onRefresh,
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(child: _pages.elementAt(_selectedIndex)),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
      floatingActionButton:
          _isApprovedVendor && (_selectedIndex == 0 || _selectedIndex == 1)
          ? FloatingActionButton.extended(
              onPressed: _openAddProduct,
              backgroundColor: _primaryNavy,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Product',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  List<dynamic> _readNotifications(Map<String, dynamic> user) {
    return user['notifications'] is List
        ? List<dynamic>.from(user['notifications'] as List)
        : <dynamic>[];
  }

  List<dynamic> _dedupeNotifications(Iterable<dynamic> rawItems) {
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];

    for (final raw in rawItems) {
      final item = _notificationMap(raw);
      if (item.isEmpty) continue;
      final key = _notificationFingerprint(item);
      if (key.isEmpty || seen.add(key)) {
        result.add(item);
      }
    }

    result.sort((a, b) {
      final aDate = DateTime.tryParse(a['createdAt']?.toString() ?? '');
      final bDate = DateTime.tryParse(b['createdAt']?.toString() ?? '');
      return (bDate ?? DateTime(0)).compareTo(aDate ?? DateTime(0));
    });

    return result;
  }

  Map<String, dynamic> _notificationMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _notificationFingerprint(Map<String, dynamic> item) {
    final nestedData = _notificationMap(item['data']);
    final type =
        item['type']?.toString() ?? nestedData['type']?.toString() ?? '';
    final relatedId =
        item['relatedId']?.toString() ??
        item['orderId']?.toString() ??
        nestedData['relatedId']?.toString() ??
        nestedData['orderId']?.toString() ??
        '';
    final message = (item['message']?.toString() ?? '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final id = item['_id']?.toString() ?? item['id']?.toString() ?? '';

    if (message.isNotEmpty) return '$type|$relatedId|$message';
    return id;
  }

  String _socketNotificationMessage(
    Map<String, dynamic> data, {
    required String fallback,
  }) {
    final title = data['title']?.toString().trim() ?? '';
    final message = data['message']?.toString().trim() ?? '';

    if (title.isNotEmpty &&
        message.isNotEmpty &&
        !message.toLowerCase().startsWith('${title.toLowerCase()}:')) {
      return '$title: $message';
    }

    return message.isNotEmpty ? message : fallback;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
