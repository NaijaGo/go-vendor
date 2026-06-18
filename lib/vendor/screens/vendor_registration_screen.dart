import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants.dart';
import '../../core/image_upload_mime.dart';
import '../../services/address_resolution_service.dart';
import '../../services/location_access_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';

const Color _vendorNavy = Color(0xFF03024C);
const Color _vendorBlue = Color(0xFF0D2E91);
const Color _vendorMint = Color(0xFFB7FFD4);
const Color _vendorSoftText = Color(0xFFD9E4F6);

class VendorRegistrationScreen extends StatefulWidget {
  const VendorRegistrationScreen({super.key});

  @override
  State<VendorRegistrationScreen> createState() =>
      _VendorRegistrationScreenState();
}

class _VendorRegistrationScreenState extends State<VendorRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _alternatePhoneController =
      TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _businessNameController = TextEditingController();
  final TextEditingController _formattedAddressController =
      TextEditingController();
  final TextEditingController _shopZoneController = TextEditingController();
  final TextEditingController _shopCityController = TextEditingController();
  final TextEditingController _manualLatitudeController =
      TextEditingController();
  final TextEditingController _manualLongitudeController =
      TextEditingController();
  final TextEditingController _deliveryZoneController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _productPriceController = TextEditingController();
  final TextEditingController _productDescriptionController =
      TextEditingController();
  final TextEditingController _socialMediaController = TextEditingController();
  final TextEditingController _cacNumberController = TextEditingController();
  final TextEditingController _bankAccountNameController =
      TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _bankAccountNumberController =
      TextEditingController();
  final TextEditingController _emergencyContactController =
      TextEditingController();
  final TextEditingController _openTimeController = TextEditingController(
    text: '09:00',
  );
  final TextEditingController _closeTimeController = TextEditingController(
    text: '19:00',
  );

  double? _businessLocationLatitude;
  double? _businessLocationLongitude;
  String? _selectedGender;
  String? _selectedIdType;
  final List<String> _selectedCategories = [];
  final List<String> _deliveryZones = [];
  final Set<String> _selectedOperatingDays = {
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
  };
  String? _idDocumentUrl;
  final List<String> _shopPhotoUrls = [];
  final List<String> _productPhotoUrls = [];
  String? _cacCertificateUrl;
  bool _deliveryAvailable = true;
  bool _termsAccepted = false;
  bool _obligationsAccepted = false;
  bool _prohibitedProductsAccepted = false;
  bool _isSubmitting = false;
  bool _isLocating = false;
  bool _isUploadingFile = false;
  String? _errorMessage;
  String? _successMessage;

  final List<String> _genderOptions = ['Male', 'Female', 'Other'];
  final Map<String, String> _idTypeOptions = const {
    'national_id': 'National ID',
    'voters_card': "Voter's Card",
    'drivers_license': "Driver's License",
    'international_passport': 'International Passport',
  };
  final Map<String, String> _dayLabels = const {
    'monday': 'Mon',
    'tuesday': 'Tue',
    'wednesday': 'Wed',
    'thursday': 'Thu',
    'friday': 'Fri',
    'saturday': 'Sat',
    'sunday': 'Sun',
  };
  final List<String> _categoryOptions = [
    'Supermarkets',
    'Boutiques',
    'Phone Accessories',
    'Health and Pharmacies',
    'Electronics',
    'Fashion',
    'Food & Beverages',
    'Services',
    'Automotive',
    'Books & Stationery',
    'Home & Kitchen',
    'Sports & Outdoors',
    'Toys & Games',
    'Pet Supplies',
    'Art & Crafts',
    'Jewelry',
    'Beauty & Personal Care',
    'Baby Products',
    'Industrial & Scientific',
    'Musical Instruments',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _alternatePhoneController.dispose();
    _whatsappController.dispose();
    _emailController.dispose();
    _businessNameController.dispose();
    _formattedAddressController.dispose();
    _shopZoneController.dispose();
    _shopCityController.dispose();
    _manualLatitudeController.dispose();
    _manualLongitudeController.dispose();
    _deliveryZoneController.dispose();
    _idNumberController.dispose();
    _productPriceController.dispose();
    _productDescriptionController.dispose();
    _socialMediaController.dispose();
    _cacNumberController.dispose();
    _bankAccountNameController.dispose();
    _bankNameController.dispose();
    _bankAccountNumberController.dispose();
    _emergencyContactController.dispose();
    _openTimeController.dispose();
    _closeTimeController.dispose();
    super.dispose();
  }

  Future<void> _getRealBusinessLocation() async {
    if (_isLocating) return;

    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });

    try {
      final locationAccess = await LocationAccessService.ensureAccess();
      if (!locationAccess.granted) {
        setState(() {
          _errorMessage = locationAccess.message;
        });
        if (mounted) {
          await LocationAccessService.presentIssue(context, locationAccess);
        }
        return;
      }

      await LocationAccessService.requestPreciseLocationIfNeeded();

      final position = await _getCurrentBusinessPosition();

      ResolvedAddress? resolvedAddress;
      try {
        resolvedAddress = await AddressResolutionService.resolveFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 12));
      } catch (error) {
        debugPrint('Business reverse geocoding failed: $error');
      }

      if (!mounted) return;
      setState(() {
        _businessLocationLatitude = position.latitude;
        _businessLocationLongitude = position.longitude;
        if (resolvedAddress != null) {
          _formattedAddressController.text = resolvedAddress.formattedAddress;
          if (resolvedAddress.city.isNotEmpty) {
            _shopCityController.text = resolvedAddress.city;
          }
        } else if (_formattedAddressController.text.trim().isEmpty) {
          _formattedAddressController.text =
              'GPS coordinates captured. Please confirm the shop address manually.';
        }
        _manualLatitudeController.text = position.latitude.toStringAsFixed(6);
        _manualLongitudeController.text = position.longitude.toStringAsFixed(6);
      });
      _showSnack(
        resolvedAddress == null
            ? 'GPS coordinates captured. Please confirm the address fields.'
            : 'Business location captured successfully.',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _businessLocationFailureMessage(e);
        });
      }
      debugPrint('Location error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<Position> _getCurrentBusinessPosition() async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationAccessService.currentLocationSettings(),
        ).timeout(const Duration(seconds: 18));
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        final shouldRetry =
            _isPluginNotInitializedError(error) || error is TimeoutException;
        if (!shouldRetry || attempt == 3) {
          break;
        }

        await Future<void>.delayed(Duration(milliseconds: 500 + attempt * 300));
      }
    }

    final lastKnownPosition = await Geolocator.getLastKnownPosition();
    if (lastKnownPosition != null) {
      return lastKnownPosition;
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  bool _isPluginNotInitializedError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('notinitializederror') ||
        normalized.contains('notlnitializederror') ||
        normalized.contains('not initialized');
  }

  String _businessLocationFailureMessage(Object error) {
    if (_isPluginNotInitializedError(error)) {
      return 'Location is still starting on this phone. Please wait a moment and try again.';
    }

    if (error is TimeoutException) {
      return 'Current location took too long. Please check your signal and try again, or enter the shop coordinates manually.';
    }

    return 'Failed to get location. Please check location access, or enter the shop address and coordinates manually.';
  }

  Future<void> _openLocationPicker() async {
    final addressController = TextEditingController(
      text: _formattedAddressController.text,
    );
    final zoneController = TextEditingController(
      text: _shopZoneController.text,
    );
    final cityController = TextEditingController(
      text: _shopCityController.text,
    );
    final latitudeController = TextEditingController(
      text: _manualLatitudeController.text,
    );
    final longitudeController = TextEditingController(
      text: _manualLongitudeController.text,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppTheme.borderGrey,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Pick shop location',
                    style: TextStyle(
                      color: AppTheme.secondaryBlack,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter the shop address and zone. Latitude and longitude are optional when GPS is unavailable.',
                    style: TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addressController,
                    maxLines: 3,
                    decoration: _inputDecoration(
                      label: 'Business/shop address',
                      icon: Icons.location_on_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: zoneController,
                    decoration: _inputDecoration(
                      label: 'Shop zone/area',
                      icon: Icons.map_outlined,
                      hint: 'Example: Wuse 2, Gwarinpa, Lekki Phase 1',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cityController,
                    decoration: _inputDecoration(
                      label: 'City',
                      icon: Icons.location_city_outlined,
                      hint: 'Example: Abuja',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: _inputDecoration(
                            label: 'Latitude',
                            icon: Icons.explore_outlined,
                            hint: 'Optional',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: longitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: _inputDecoration(
                            label: 'Longitude',
                            icon: Icons.explore,
                            hint: 'Optional',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLocating
                              ? null
                              : () async {
                                  Navigator.of(sheetContext).pop();
                                  await _getRealBusinessLocation();
                                },
                          icon: const Icon(Icons.my_location_rounded),
                          label: const Text('Use GPS'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final latitude = double.tryParse(
                              latitudeController.text.trim(),
                            );
                            final longitude = double.tryParse(
                              longitudeController.text.trim(),
                            );
                            setState(() {
                              _formattedAddressController.text =
                                  addressController.text.trim();
                              _shopZoneController.text = zoneController.text
                                  .trim();
                              _shopCityController.text = cityController.text
                                  .trim();
                              _manualLatitudeController.text =
                                  latitudeController.text.trim();
                              _manualLongitudeController.text =
                                  longitudeController.text.trim();
                              _businessLocationLatitude = latitude;
                              _businessLocationLongitude = longitude;
                            });
                            Navigator.of(sheetContext).pop();
                          },
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Apply'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _vendorNavy,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _addDeliveryZone() {
    final zone = _deliveryZoneController.text.trim();
    if (zone.isEmpty || _deliveryZones.contains(zone)) return;
    setState(() {
      _deliveryZones.add(zone);
      _deliveryZoneController.clear();
    });
  }

  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && token.isNotEmpty) return token;

    if (!mounted) return null;
    _showSnack(
      'Please log in first, then open Vendor onboarding from the Vendor tab.',
    );
    return null;
  }

  Future<void> _pickAndUploadOnboardingImage({
    required String purpose,
    required void Function(String url) onUploaded,
  }) async {
    if (_isUploadingFile) return;

    final token = await _getAuthToken();
    if (token == null) return;

    XFile? image;
    try {
      image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );
    } on PlatformException catch (error) {
      debugPrint('Image picker error: $error');
      _showSnack(
        'Photo access failed. On iPhone, allow Photos access for Go-Vendor in Settings.',
      );
      return;
    }

    if (image == null) {
      _showSnack('No photo selected.');
      return;
    }
    if (!mounted) return;

    setState(() => _isUploadingFile = true);
    try {
      final request =
          http.MultipartRequest(
              'POST',
              Uri.parse('$baseUrl/api/uploads/cloudinary/vendor-onboarding'),
            )
            ..headers['Authorization'] = 'Bearer $token'
            ..fields['purpose'] = purpose;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          await image.readAsBytes(),
          filename: imageUploadFilename(
            fallback: purpose,
            filename: image.name,
            path: image.path,
          ),
          contentType: imageUploadContentType(
            filename: image.name,
            path: image.path,
          ),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final body = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200 && body['url'] != null) {
        if (!mounted) return;
        setState(() => onUploaded(body['url'].toString()));
        _showSnack('Upload complete.');
      } else {
        _showSnack(body['message']?.toString() ?? 'Upload failed.');
      }
    } catch (error) {
      _showSnack('Unable to upload file: $error');
    } finally {
      if (mounted) {
        setState(() => _isUploadingFile = false);
      }
    }
  }

  Future<void> _submitVendorRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_termsAccepted) {
      setState(() {
        _errorMessage = 'You must accept the Vendor Agreement.';
      });
      return;
    }

    if (!_obligationsAccepted || !_prohibitedProductsAccepted) {
      setState(() {
        _errorMessage =
            'Please accept the vendor obligations and prohibited product rules.';
      });
      return;
    }

    if (_selectedCategories.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one business category.';
      });
      return;
    }

    if (_selectedIdType == null || _idDocumentUrl == null) {
      setState(() {
        _errorMessage = 'Please select and upload a valid means of ID.';
      });
      return;
    }

    if (_shopPhotoUrls.isEmpty || _productPhotoUrls.isEmpty) {
      setState(() {
        _errorMessage =
            'Please upload at least one clear shop picture and one product picture.';
      });
      return;
    }

    if (_selectedOperatingDays.isEmpty) {
      setState(() {
        _errorMessage = 'Please select your operating days.';
      });
      return;
    }

    if (_formattedAddressController.text.trim().isEmpty ||
        _shopZoneController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please provide your business address and shop zone.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final token = await _getAuthToken();

    if (token == null) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              'Please log in first, then open Vendor onboarding from the Vendor tab.';
        });
      }
      return;
    }

    final requestBody = <String, dynamic>{
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'activePhoneNumber': _alternatePhoneController.text.trim(),
      'alternatePhoneNumber': _alternatePhoneController.text.trim(),
      'whatsappNumber': _whatsappController.text.trim(),
      'vendorContactEmail': _emailController.text.trim(),
      'gender': _selectedGender,
      'businessName': _businessNameController.text.trim(),
      'businessCategories': _selectedCategories,
      'termsAccepted': _termsAccepted,
      'businessLocation': {
        'latitude': _businessLocationLatitude,
        'longitude': _businessLocationLongitude,
        'formattedAddress': _formattedAddressController.text.trim(),
        'zone': _shopZoneController.text.trim(),
        'city': _shopCityController.text.trim(),
      },
      'validIdentification': {
        'idType': _selectedIdType,
        'idNumber': _idNumberController.text.trim(),
        'documentUrl': _idDocumentUrl,
      },
      'shopPhotoUrls': _shopPhotoUrls,
      'sampleProducts': [
        {
          'price': double.tryParse(_productPriceController.text.trim()) ?? 0,
          'description': _productDescriptionController.text.trim(),
          'photoUrls': _productPhotoUrls,
        },
      ],
      'socialMediaPage': _socialMediaController.text.trim(),
      'cacNumber': _cacNumberController.text.trim(),
      'cacCertificateUrl': _cacCertificateUrl,
      'bankAccountDetails': {
        'accountName': _bankAccountNameController.text.trim(),
        'bankName': _bankNameController.text.trim(),
        'accountNumber': _bankAccountNumberController.text.trim(),
      },
      'operatingHours': _dayLabels.keys.map((day) {
        return {
          'day': day,
          'isOpen': _selectedOperatingDays.contains(day),
          'openTime': _openTimeController.text.trim(),
          'closeTime': _closeTimeController.text.trim(),
          'lastOrderTime': _closeTimeController.text.trim(),
        };
      }).toList(),
      'deliveryZones': _deliveryZones,
      'deliveryAvailable': _deliveryAvailable,
      'emergencyContactNumber': _emergencyContactController.text.trim(),
      'vendorAgreements': {
        'respondQuickly': _obligationsAccepted,
        'prepareOrdersOnTime': _obligationsAccepted,
        'keepProductsUpdated': _obligationsAccepted,
        'maintainAccuratePricing': _obligationsAccepted,
        'packageItemsProperly': _obligationsAccepted,
        'treatCustomersProfessionally': _obligationsAccepted,
        'followNaijaGoPolicies': _obligationsAccepted,
        'avoidFakeOrProhibitedProducts': _obligationsAccepted,
      },
      'prohibitedProductsAcknowledged': _prohibitedProductsAccepted,
    };

    try {
      final url = Uri.parse('$baseUrl/api/vendor/request');
      final response = await http.post(
        url,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) {
        return;
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final message =
            responseData['message']?.toString() ??
            'Vendor request submitted successfully!';
        setState(() {
          _successMessage = message;
        });
        _showSnack(message);
        Navigator.of(context).pop();
      } else {
        setState(() {
          _errorMessage =
              responseData['message']?.toString() ??
              'Failed to submit vendor request.';
        });
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'An error occurred: $e. Please ensure the backend is available.';
      });
      debugPrint('Vendor request network error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showTermsAndConditions() {
    final todayDate = DateFormat('MMMM d, yyyy').format(DateTime.now());
    final agreement =
        '''
VENDOR AGREEMENT

This Vendor Agreement is made on $todayDate.

BETWEEN:
NAIJAGO APP LTD with RC No: 8704653 situated at Efab Queens Estate, Gwarinpa, Abuja.

AND:
[Vendor Name / RC No. will be captured from form data] situated at [Vendor Location will be captured from form data] ("Vendor").

BACKGROUND

a. NaijaGo operates a technology platform consisting of a website and mobile application which facilitates the marketing and sale of products and services from vendors to customers.
b. The Vendor is engaged in the business of selling products and/or services and wishes to utilize the Platform to market and sell its products and services.
c. The Parties now wish to set forth the terms and conditions under which the Vendor shall utilize the Platform.

IT IS HEREBY AGREED AS FOLLOWS:

1. DEFINITIONS
a. "Bimp Service" means the feature on the Platform that allows Customers to request and receive real-time products and services employed by the Vendor.
b. "Customer" means any end-user who places an Order via the Platform.
c. "Order" means a request for Products or Services placed by a Customer through the Platform.
d. "Products" means the goods offered for sale by the Vendor on the Platform.
e. "Services" means the Bimp Service and any other services offered by the Vendor.

2. APPOINTMENT AND LISTING
a. NaijaGo hereby grants the Vendor a non-exclusive, non-transferable right to display, market, and sell its Products and Services on the Platform during the term of this Agreement.
b. The Vendor grants NaijaGo the right to use its trademarks, logos, and product images for the purpose of marketing and promotion on the Platform.

3. VENDOR OBLIGATIONS AND WARRANTIES
The Vendor warrants that:
a. It holds all necessary licenses, permits, and approvals, including for pharmacists a valid PCN license, to sell its Products and provide its Services in Nigeria.
b. All Products are genuine, safe, not expired, and conform to all applicable descriptions and quality standards.
c. It will respond to a Bimp Service notification within sixty (60) seconds of the alert and provide professional, diligent, and compliant consultancy services.
d. It will process and prepare Orders for dispatch within the agreed Service Level Agreement provided by NaijaGo.
e. It is solely responsible for the accuracy, quality, and legality of the Products and Services it lists.

4. FINANCIAL TERMS
a. Commission: NaijaGo will charge a commission of 15% of the Gross Sale Price of each Order fulfilled.
b. Payment to Vendor: NaijaGo shall remit payment to the Vendor for completed Orders, less the commission, immediately after successful delivery to the Customer.
c. Taxes: Each party is responsible for its own taxes arising from this Agreement.

5. DATA PROTECTION AND INTELLECTUAL PROPERTY
a. Both parties agree to comply with the Nigeria Data Protection Act (NDPA), 2023. The Vendor shall treat all Customer data as confidential.
b. All intellectual property rights in the Platform, including the Bimp technology and feature, remain the sole and exclusive property of NaijaGo.

6. LIMITATION OF LIABILITY AND INDEMNITY
a. NaijaGo's role is limited to providing the Platform. NaijaGo is not a party to the contract of sale and shall not be liable for the quality, safety, or legality of the Vendor's Products or Services.
b. The Vendor shall indemnify and hold NaijaGo harmless against all claims, losses, damages, and expenses arising from the Vendor's breach of this Agreement.

7. TERM AND TERMINATION
a. This Agreement shall commence on the effective date and continue for a period of one (1) year, thereafter automatically renewing.
b. Either party may terminate with thirty (30) days written notice.
c. NaijaGo may suspend the Vendor's account or terminate this Agreement immediately for breaches of the Vendor obligations or data protection clauses.

8. GOVERNING LAW AND DISPUTE RESOLUTION
a. This Agreement shall be governed by and construed in accordance with the laws of the Federal Republic of Nigeria.
b. Disputes shall be referred to a single arbitrator in accordance with the Arbitration and Conciliation Act. The seat of arbitration shall be Abuja.
''';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 52,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppTheme.borderGrey,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _vendorNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.verified_user_outlined,
                          color: _vendorNavy,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Vendor Agreement',
                          style: TextStyle(
                            color: AppTheme.secondaryBlack,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: SelectableText(
                      agreement,
                      style: const TextStyle(
                        color: AppTheme.secondaryBlack,
                        fontSize: 13.5,
                        height: 1.65,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.secondaryBlack,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String? _validateRequiredPhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return 'Please enter a phone number';
    }
    final pattern = RegExp(r'^(?:\+?234|0)[789]\d{9}$');
    if (!pattern.hasMatch(trimmed)) {
      return 'Enter a valid Nigerian phone number';
    }
    return null;
  }

  String? _validateOptionalEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final pattern = RegExp(r'^.+@.+\..+$');
    if (!pattern.hasMatch(trimmed)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validateRequiredText(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppTheme.mutedText),
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: AppTheme.mutedText, fontSize: 14),
      hintStyle: const TextStyle(color: AppTheme.mutedText, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 18,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.borderGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.primaryNavy, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.dangerRed, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppTheme.dangerRed, width: 1.4),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_vendorNavy, _vendorBlue, AppTheme.primaryNavy],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -24,
            right: -16,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _vendorMint.withValues(alpha: 0.10),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: 16,
                      color: _vendorMint,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'NaijaGo Seller Hub',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Bring your business to customers across Nigeria',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  height: 1.08,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'This is a vendor onboarding flow, separate from customer sign up. Submit your business details, verify your location, and request seller approval.',
                style: TextStyle(
                  color: _vendorSoftText,
                  fontSize: 14.5,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _HeroPill(
                    icon: Icons.badge_outlined,
                    label: 'Business identity',
                  ),
                  _HeroPill(
                    icon: Icons.location_on_outlined,
                    label: 'Location verification',
                  ),
                  _HeroPill(
                    icon: Icons.approval_outlined,
                    label: 'Seller review',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerSection() {
    return _SectionCard(
      icon: Icons.badge_outlined,
      title: "Owner's Full Name & Contact",
      subtitle:
          'Enter the account owner, active phone number, WhatsApp number, and optional email address.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 560;

          final firstNameField = TextFormField(
            controller: _firstNameController,
            decoration: _inputDecoration(
              label: 'First name',
              icon: Icons.person_outline_rounded,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your first name';
              }
              return null;
            },
          );

          final lastNameField = TextFormField(
            controller: _lastNameController,
            decoration: _inputDecoration(
              label: 'Last name',
              icon: Icons.badge_outlined,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your last name';
              }
              return null;
            },
          );

          final genderField = DropdownButtonFormField<String>(
            value: _selectedGender,
            decoration:
                _inputDecoration(
                  label: 'Gender',
                  icon: Icons.wc_rounded,
                ).copyWith(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
            dropdownColor: Colors.white,
            items: _genderOptions.map((gender) {
              return DropdownMenuItem<String>(
                value: gender,
                child: Text(gender),
              );
            }).toList(),
            onChanged: (newValue) {
              setState(() {
                _selectedGender = newValue;
              });
            },
            validator: (value) {
              if (value == null) {
                return 'Please select your gender';
              }
              return null;
            },
          );

          if (wide) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: firstNameField),
                    const SizedBox(width: 14),
                    Expanded(child: lastNameField),
                  ],
                ),
                const SizedBox(height: 14),
                genderField,
                const SizedBox(height: 14),
                TextFormField(
                  controller: _alternatePhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(
                    label: 'Active phone number',
                    icon: Icons.phone_outlined,
                    hint: 'Contact number for buyers and support',
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty) {
                      return 'Please enter an active phone number';
                    }
                    final pattern = RegExp(r'^(?:\+?234|0)[789]\d{9}$');
                    if (!pattern.hasMatch(trimmed)) {
                      return 'Enter a valid Nigerian phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _whatsappController,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDecoration(
                    label: 'Active WhatsApp number',
                    icon: Icons.chat_outlined,
                  ),
                  validator: _validateRequiredPhone,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDecoration(
                    label: 'Business email',
                    icon: Icons.email_outlined,
                    hint: 'Optional',
                  ),
                  validator: _validateOptionalEmail,
                ),
              ],
            );
          }

          return Column(
            children: [
              firstNameField,
              const SizedBox(height: 14),
              lastNameField,
              const SizedBox(height: 14),
              genderField,
              const SizedBox(height: 14),
              TextFormField(
                controller: _alternatePhoneController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration(
                  label: 'Active phone number',
                  icon: Icons.phone_outlined,
                  hint: 'Contact number for buyers and support',
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Please enter an active phone number';
                  }
                  final pattern = RegExp(r'^(?:\+?234|0)[789]\d{9}$');
                  if (!pattern.hasMatch(trimmed)) {
                    return 'Enter a valid Nigerian phone number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration(
                  label: 'Active WhatsApp number',
                  icon: Icons.chat_outlined,
                ),
                validator: _validateRequiredPhone,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration(
                  label: 'Business email',
                  icon: Icons.email_outlined,
                  hint: 'Optional',
                ),
                validator: _validateOptionalEmail,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBusinessSection() {
    final hasLocation =
        _businessLocationLatitude != null && _businessLocationLongitude != null;

    return _SectionCard(
      icon: Icons.store_mall_directory_outlined,
      title: 'Full Business Name & Shop Address',
      subtitle:
          'Enter the full business name and capture the business/shop address.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _businessNameController,
            decoration: _inputDecoration(
              label: 'Business name',
              icon: Icons.storefront_outlined,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your business name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Text(
            'Business/shop address',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Use GPS or pick the shop address and zone manually so nearby customers can discover your store accurately.',
            style: TextStyle(
              color: AppTheme.mutedText,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _formattedAddressController,
            readOnly: true,
            decoration: _inputDecoration(
              label: 'Verified business/shop address',
              icon: Icons.location_on_outlined,
              hint: 'Use GPS or pick location manually',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please provide a business address';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _shopZoneController,
            readOnly: true,
            decoration: _inputDecoration(
              label: 'Shop zone/area',
              icon: Icons.map_outlined,
              hint: 'Example: Wuse 2, Gwarinpa, Lekki Phase 1',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please add your shop zone or area';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _shopCityController,
            readOnly: true,
            decoration: _inputDecoration(
              label: 'City',
              icon: Icons.location_city_outlined,
              hint: 'Optional',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLocating ? null : _getRealBusinessLocation,
                  icon: _isLocating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.my_location_rounded),
                  label: Text(
                    _isLocating
                        ? 'Capturing location...'
                        : 'Use current location',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openLocationPicker,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Pick location'),
                ),
              ),
            ],
          ),
          if (hasLocation) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFFAF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.accentGreen.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.verified_outlined,
                      size: 18,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Verified coordinates: ${_businessLocationLatitude!.toStringAsFixed(5)}, ${_businessLocationLongitude!.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: AppTheme.secondaryBlack,
                        fontSize: 12.8,
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return _SectionCard(
      icon: Icons.grid_view_rounded,
      title: 'Business Category',
      subtitle:
          'Choose every category that matches what your business actually sells.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _selectedCategories.isEmpty
                  ? 'No categories selected yet.'
                  : '${_selectedCategories.length} category${_selectedCategories.length == 1 ? '' : 'ies'} selected.',
              style: const TextStyle(
                color: AppTheme.secondaryBlack,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _categoryOptions.map((category) {
              final isSelected = _selectedCategories.contains(category);
              return FilterChip(
                label: Text(category),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedCategories.add(category);
                    } else {
                      _selectedCategories.remove(category);
                    }
                  });
                },
                backgroundColor: Colors.white,
                selectedColor: AppTheme.primaryNavy.withValues(alpha: 0.12),
                checkmarkColor: AppTheme.primaryNavy,
                labelStyle: TextStyle(
                  color: isSelected
                      ? AppTheme.primaryNavy
                      : AppTheme.secondaryBlack,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryNavy.withValues(alpha: 0.22)
                      : AppTheme.borderGrey,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationSection() {
    return _SectionCard(
      icon: Icons.fact_check_outlined,
      title: 'Required Documents Upload',
      subtitle:
          'Upload a valid ID, clear shop photos, clear product photos, and CAC certificate if available.',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: _selectedIdType,
            decoration: _inputDecoration(
              label: 'Valid means of identification',
              icon: Icons.badge_outlined,
            ),
            items: _idTypeOptions.entries.map((entry) {
              return DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: (value) => setState(() => _selectedIdType = value),
            validator: (value) =>
                value == null ? 'Please select an ID type' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _idNumberController,
            decoration: _inputDecoration(
              label: 'ID number',
              icon: Icons.confirmation_number_outlined,
              hint: 'Optional if not printed clearly',
            ),
          ),
          const SizedBox(height: 14),
          _UploadTile(
            title: 'Valid ID',
            subtitle: _idDocumentUrl == null ? 'Required' : 'Uploaded',
            count: _idDocumentUrl == null ? 0 : 1,
            isUploading: _isUploadingFile,
            onPressed: () => _pickAndUploadOnboardingImage(
              purpose: 'valid-id',
              onUploaded: (url) => _idDocumentUrl = url,
            ),
          ),
          const SizedBox(height: 10),
          _UploadTile(
            title: 'Shop photos',
            subtitle: 'At least one required',
            count: _shopPhotoUrls.length,
            isUploading: _isUploadingFile,
            onPressed: () => _pickAndUploadOnboardingImage(
              purpose: 'shop-photo',
              onUploaded: _shopPhotoUrls.add,
            ),
          ),
          const SizedBox(height: 10),
          _UploadTile(
            title: 'Product photos',
            subtitle: 'At least one required',
            count: _productPhotoUrls.length,
            isUploading: _isUploadingFile,
            onPressed: () => _pickAndUploadOnboardingImage(
              purpose: 'product-photo',
              onUploaded: _productPhotoUrls.add,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductAndBusinessDetailsSection() {
    return _SectionCard(
      icon: Icons.inventory_2_outlined,
      title: 'Product Prices & Descriptions',
      subtitle:
          'Add a product price, product description, optional social media page, and optional CAC details.',
      child: Column(
        children: [
          TextFormField(
            controller: _productPriceController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration(
              label: 'Product price',
              icon: Icons.payments_outlined,
              hint: 'Example: 2500',
            ),
            validator: (value) {
              final price = double.tryParse(value?.trim() ?? '');
              if (price == null || price <= 0) {
                return 'Please enter a valid product price';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _productDescriptionController,
            maxLines: 4,
            decoration: _inputDecoration(
              label: 'Product description',
              icon: Icons.description_outlined,
            ),
            validator: (value) =>
                _validateRequiredText(value, 'Please describe a product'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _socialMediaController,
            decoration: _inputDecoration(
              label: 'Social media page',
              icon: Icons.alternate_email_rounded,
              hint: 'Optional',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _cacNumberController,
            decoration: _inputDecoration(
              label: 'CAC number',
              icon: Icons.business_center_outlined,
              hint: 'Optional but recommended',
            ),
          ),
          const SizedBox(height: 10),
          _UploadTile(
            title: 'CAC certificate',
            subtitle: _cacCertificateUrl == null
                ? 'Optional but recommended'
                : 'Uploaded',
            count: _cacCertificateUrl == null ? 0 : 1,
            isUploading: _isUploadingFile,
            onPressed: () => _pickAndUploadOnboardingImage(
              purpose: 'cac-certificate',
              onUploaded: (url) => _cacCertificateUrl = url,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationsSection() {
    return _SectionCard(
      icon: Icons.schedule_outlined,
      title: 'Bank Details, Hours & Delivery',
      subtitle:
          'Enter bank account details, operating days and hours, delivery availability, and emergency contact.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _bankAccountNameController,
            decoration: _inputDecoration(
              label: 'Account name',
              icon: Icons.account_circle_outlined,
            ),
            validator: (value) =>
                _validateRequiredText(value, 'Please enter account name'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _bankNameController,
            decoration: _inputDecoration(
              label: 'Bank name',
              icon: Icons.account_balance_outlined,
            ),
            validator: (value) =>
                _validateRequiredText(value, 'Please enter bank name'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _bankAccountNumberController,
            keyboardType: TextInputType.number,
            decoration: _inputDecoration(
              label: 'Account number',
              icon: Icons.numbers_outlined,
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (!RegExp(r'^\d{10}$').hasMatch(trimmed)) {
                return 'Account number must be 10 digits';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          const Text(
            'Operating days',
            style: TextStyle(
              color: AppTheme.secondaryBlack,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dayLabels.entries.map((entry) {
              final selected = _selectedOperatingDays.contains(entry.key);
              return FilterChip(
                label: Text(entry.value),
                selected: selected,
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _selectedOperatingDays.add(entry.key);
                    } else {
                      _selectedOperatingDays.remove(entry.key);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _openTimeController,
                  decoration: _inputDecoration(
                    label: 'Open time',
                    icon: Icons.access_time,
                    hint: 'HH:mm',
                  ),
                  validator: (value) =>
                      RegExp(
                        r'^([01]\d|2[0-3]):[0-5]\d$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use HH:mm',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _closeTimeController,
                  decoration: _inputDecoration(
                    label: 'Close time',
                    icon: Icons.access_time_filled,
                    hint: 'HH:mm',
                  ),
                  validator: (value) =>
                      RegExp(
                        r'^([01]\d|2[0-3]):[0-5]\d$',
                      ).hasMatch(value?.trim() ?? '')
                      ? null
                      : 'Use HH:mm',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile.adaptive(
            value: _deliveryAvailable,
            onChanged: (value) => setState(() => _deliveryAvailable = value),
            title: const Text('Delivery available'),
            contentPadding: EdgeInsets.zero,
            activeColor: AppTheme.primaryNavy,
          ),
          if (_deliveryAvailable) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _deliveryZoneController,
                    decoration: _inputDecoration(
                      label: 'Add delivery zone',
                      icon: Icons.add_location_alt_outlined,
                      hint: 'Example: Maitama, Wuse, Garki',
                    ),
                    onFieldSubmitted: (_) => _addDeliveryZone(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: _addDeliveryZone,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add delivery zone',
                  style: IconButton.styleFrom(
                    backgroundColor: _vendorNavy,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            if (_deliveryZones.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _deliveryZones.map((zone) {
                  return InputChip(
                    label: Text(zone),
                    onDeleted: () {
                      setState(() => _deliveryZones.remove(zone));
                    },
                  );
                }).toList(),
              ),
            ],
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _emergencyContactController,
            keyboardType: TextInputType.phone,
            decoration: _inputDecoration(
              label: 'Emergency contact number',
              icon: Icons.contact_emergency_outlined,
            ),
            validator: _validateRequiredPhone,
          ),
        ],
      ),
    );
  }

  Widget _buildAgreementSection() {
    return _SectionCard(
      icon: Icons.verified_user_outlined,
      title: 'Vendor Must Agree To',
      subtitle:
          'Confirm seller obligations and prohibited product rules before submitting.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.borderGrey),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _termsAccepted,
                  onChanged: (newValue) {
                    setState(() {
                      _termsAccepted = newValue ?? false;
                    });
                  },
                  activeColor: AppTheme.primaryNavy,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'I have read and agree to the NaijaGo Vendor Agreement, platform obligations, and seller verification requirements.',
                      style: TextStyle(
                        color: AppTheme.secondaryBlack,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _showTermsAndConditions,
            icon: const Icon(Icons.description_outlined),
            label: const Text('Read vendor agreement'),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _obligationsAccepted,
            onChanged: (value) {
              setState(() => _obligationsAccepted = value ?? false);
            },
            activeColor: AppTheme.primaryNavy,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I agree to respond quickly, prepare orders on time, keep products and prices accurate, package items properly, treat customers professionally, follow NaijaGo policies, and avoid fake or prohibited products.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ),
          CheckboxListTile(
            value: _prohibitedProductsAccepted,
            onChanged: (value) {
              setState(() => _prohibitedProductsAccepted = value ?? false);
            },
            activeColor: AppTheme.primaryNavy,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'I acknowledge that illegal items, counterfeit products, weapons, hard drugs, fraud-related items, and adult/prohibited materials cannot be sold on NaijaGo.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner({
    required Color backgroundColor,
    required Color borderColor,
    required Color textColor,
    required IconData icon,
    required String message,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitSection() {
    final hasLocation =
        _businessLocationLatitude != null && _businessLocationLongitude != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ready to submit?',
            style: TextStyle(
              color: AppTheme.secondaryBlack,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Owner details, business identity, verified location, and category coverage all feed into your seller review.',
            style: TextStyle(
              color: AppTheme.mutedText,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SummaryChip(
                label: _selectedCategories.isEmpty
                    ? 'Categories pending'
                    : '${_selectedCategories.length} categories selected',
                isComplete: _selectedCategories.isNotEmpty,
              ),
              _SummaryChip(
                label: hasLocation ? 'Location verified' : 'Location pending',
                isComplete: hasLocation,
              ),
              _SummaryChip(
                label: _idDocumentUrl == null ? 'ID pending' : 'ID uploaded',
                isComplete: _idDocumentUrl != null,
              ),
              _SummaryChip(
                label: _shopPhotoUrls.isEmpty
                    ? 'Shop photos pending'
                    : '${_shopPhotoUrls.length} shop photo${_shopPhotoUrls.length == 1 ? '' : 's'}',
                isComplete: _shopPhotoUrls.isNotEmpty,
              ),
              _SummaryChip(
                label: _productPhotoUrls.isEmpty
                    ? 'Product photos pending'
                    : '${_productPhotoUrls.length} product photo${_productPhotoUrls.length == 1 ? '' : 's'}',
                isComplete: _productPhotoUrls.isNotEmpty,
              ),
              _SummaryChip(
                label: _termsAccepted
                    ? 'Agreement accepted'
                    : 'Agreement pending',
                isComplete: _termsAccepted,
              ),
              _SummaryChip(
                label: _obligationsAccepted
                    ? 'Obligations accepted'
                    : 'Obligations pending',
                isComplete: _obligationsAccepted,
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _submitVendorRequest,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.storefront_outlined),
              label: Text(
                _isSubmitting
                    ? 'Submitting request...'
                    : 'Request vendor approval',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _vendorNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This vendor flow is separate from customer registration and is reviewed before your store goes live.',
            style: TextStyle(
              color: AppTheme.mutedText,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.softGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppTheme.secondaryBlack,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Vendor onboarding'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroCard(),
                    const SizedBox(height: 18),
                    if (_errorMessage != null)
                      _buildStatusBanner(
                        backgroundColor: AppTheme.dangerRed.withValues(
                          alpha: 0.08,
                        ),
                        borderColor: AppTheme.dangerRed.withValues(alpha: 0.18),
                        textColor: AppTheme.dangerRed,
                        icon: Icons.error_outline_rounded,
                        message: _errorMessage!,
                      ),
                    if (_successMessage != null)
                      _buildStatusBanner(
                        backgroundColor: AppTheme.accentGreen.withValues(
                          alpha: 0.10,
                        ),
                        borderColor: AppTheme.accentGreen.withValues(
                          alpha: 0.18,
                        ),
                        textColor: AppTheme.accentGreen,
                        icon: Icons.check_circle_outline_rounded,
                        message: _successMessage!,
                      ),
                    _buildOwnerSection(),
                    const SizedBox(height: 16),
                    _buildBusinessSection(),
                    const SizedBox(height: 16),
                    _buildCategoriesSection(),
                    const SizedBox(height: 16),
                    _buildVerificationSection(),
                    const SizedBox(height: 16),
                    _buildProductAndBusinessDetailsSection(),
                    const SizedBox(height: 16),
                    _buildOperationsSection(),
                    const SizedBox(height: 16),
                    _buildAgreementSection(),
                    const SizedBox(height: 18),
                    _buildSubmitSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _vendorNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _vendorNavy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppTheme.secondaryBlack,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _vendorMint),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final int count;
  final bool isUploading;
  final VoidCallback onPressed;

  const _UploadTile({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.isUploading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderGrey),
      ),
      child: Row(
        children: [
          Icon(
            count > 0 ? Icons.check_circle_outline : Icons.upload_file,
            color: count > 0 ? AppTheme.accentGreen : AppTheme.mutedText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.secondaryBlack,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count > 0 ? '$count uploaded' : subtitle,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: isUploading ? null : onPressed,
            icon: isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(isUploading ? 'Uploading' : 'Upload'),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final bool isComplete;

  const _SummaryChip({required this.label, required this.isComplete});

  @override
  Widget build(BuildContext context) {
    final color = isComplete ? AppTheme.accentGreen : AppTheme.mutedText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isComplete ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isComplete ? Icons.check_circle_outline : Icons.schedule_outlined,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
