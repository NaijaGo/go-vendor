import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class OneSignalService {
  static const String _appId = String.fromEnvironment(
    'ONESIGNAL_APP_ID',
    defaultValue: '76438b8d-4b39-49eb-805c-11eb934f5a66',
  );

  static bool _initialized = false;
  static bool _permissionRequested = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      OneSignal.initialize(_appId);
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        final data = event.notification.additionalData ?? {};
        final type = data['type']?.toString() ?? '';
        if (type == 'new_paid_order_vendor' ||
            type == 'pharmacy_consultation_request') {
          event.notification.display();
        }
      });
      OneSignal.Notifications.addClickListener((event) {
        debugPrint(
          'Vendor notification clicked: ${event.notification.additionalData}',
        );
      });
      _initialized = true;
    } catch (error) {
      debugPrint('Unable to initialize OneSignal: $error');
    }
  }

  static Future<void> requestPermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;

    try {
      final canRequest = await OneSignal.Notifications.canRequest();
      if (canRequest) {
        await OneSignal.Notifications.requestPermission(false);
      }
    } catch (error) {
      debugPrint('Unable to request OneSignal permission: $error');
    }
  }

  static Future<String?> pushSubscriptionId() async {
    try {
      final pushId = OneSignal.User.pushSubscription.id;
      return pushId == null || pushId.isEmpty ? null : pushId;
    } catch (error) {
      debugPrint('Unable to read OneSignal push subscription ID: $error');
      return null;
    }
  }

  static Future<void> loginVendor({
    required String userId,
    required String email,
    required String vendorStatus,
    required bool isVendor,
    String businessName = '',
    String pharmacistStatus = 'none',
  }) async {
    if (userId.isEmpty) return;

    try {
      await OneSignal.login(userId);
      await OneSignal.User.addTags({
        'role': isVendor ? 'vendor' : 'user',
        'vendor_id': userId,
        'user_id': userId,
        'email': email,
        'vendor_status': vendorStatus,
        'pharmacist_status': pharmacistStatus,
        'business_name': businessName,
        'last_login': DateTime.now().toIso8601String(),
      });
    } catch (error) {
      debugPrint('Unable to link vendor OneSignal account: $error');
    }
  }

  static Future<void> logout() async {
    try {
      await OneSignal.logout();
    } catch (error) {
      debugPrint('Unable to logout OneSignal vendor account: $error');
    }
  }
}
