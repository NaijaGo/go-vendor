import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/screens/login_screen.dart';
import 'constants.dart';
import 'providers/cart_provider.dart';
import 'screens/Main/vendor_app_navigator.dart';
import 'services/onesignal_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // The app can still run when environment keys are provided another way.
  }
  await OneSignalService.initialize();
  await OneSignalService.requestPermission();

  runApp(const NaijaGoVendorsApp());
}

class NaijaGoVendorsApp extends StatelessWidget {
  const NaijaGoVendorsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        title: 'NaijaGo Vendors',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const VendorSessionGate(),
      ),
    );
  }
}

class VendorSessionGate extends StatefulWidget {
  const VendorSessionGate({super.key});

  @override
  State<VendorSessionGate> createState() => _VendorSessionGateState();
}

class _VendorSessionGateState extends State<VendorSessionGate> {
  Map<String, dynamic>? _user;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVendorProfile();
  }

  Future<void> _loadVendorProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await _syncOneSignalIdentity(decoded);
        if (!mounted) return;
        setState(() {
          _user = decoded;
          _isLoading = false;
        });
        return;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await prefs.remove('jwt_token');
        if (!mounted) return;
        setState(() {
          _user = null;
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _error = 'Unable to sync vendor profile. Please try again.';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Network error while connecting to NaijaGo backend.';
        _isLoading = false;
      });
    }
  }

  Future<void> _syncOneSignalIdentity(Map<String, dynamic> user) async {
    final userId = (user['id'] ?? user['_id'] ?? '').toString();
    if (userId.isEmpty) return;

    await OneSignalService.loginVendor(
      userId: userId,
      email: user['email']?.toString() ?? '',
      vendorStatus: user['vendorStatus']?.toString() ?? 'none',
      isVendor: user['isVendor'] == true,
      businessName: user['businessName']?.toString() ?? '',
      pharmacistStatus: user['pharmacistStatus']?.toString() ?? 'none',
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await OneSignalService.logout();
    if (!mounted) return;
    setState(() {
      _user = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return LoginScreen(onLoginSuccess: _loadVendorProfile);
    }

    return VendorAppNavigator(
      user: _user!,
      syncError: _error,
      onRefresh: _loadVendorProfile,
      onLogout: _logout,
    );
  }
}
