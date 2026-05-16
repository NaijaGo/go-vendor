// lib/services/payment_service.dart
import 'package:flutter/material.dart';

class PaymentService {
  Future<dynamic> startFlutterwavePayment({
    required BuildContext context,
    required double amount,
    required String email,
    required String name,
    required String phoneNumber,
    String? userId,
  }) async {
    debugPrint(
      'PaymentService is disabled in the vendor app. '
      'Customer checkout remains in the customer app.',
    );
    return null;
  }
}
