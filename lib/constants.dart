import 'theme/app_colors.dart';
// lib/constants.dart
// This file holds constant values, such as your backend API base URL.

import 'package:flutter/material.dart';

// Backend API Base URL
// Replace with your actual backend server URL.
// For Android Emulator, '10.0.2.2' points to localhost.
// For physical device, use your computer’s IP address.
const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://naijago-backend.onrender.com',
);
const String customerSupportWhatsAppUrl = 'https://wa.me/7044332895';
const String customerSupportPhoneNumber = '7044332895';

// Cloudinary Config
const String cloudinaryUploadUrl =
    'https://api.cloudinary.com/v1_1/dbwxnt91x/image/upload';
const String cloudinaryUploadPreset =
    'unsigned_preset_here'; // Replace with your actual unsigned preset

// Colors
const Color primaryNavy = AppColors.royalBlue;
const Color secondaryBlack = AppColors.text;
const Color accentGreen = AppColors.green;
const Color softGrey = AppColors.background;
const Color lightGrey = Color(0xFF9E9E9E);
const Color white = Colors.white;
