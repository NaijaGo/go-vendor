import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../constants.dart';
import '../../widgets/pharmacy_ui.dart';
import 'chat_screen.dart';

Future<String?> _getPharmacistAuthToken() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  } catch (e) {
    debugPrint('Error retrieving pharmacist JWT token: $e');
    return null;
  }
}

class PharmacistDashboard extends StatefulWidget {
  const PharmacistDashboard({super.key});

  @override
  State<PharmacistDashboard> createState() => _PharmacistDashboardState();
}

class _PharmacistDashboardState extends State<PharmacistDashboard> {
  static const String _pharmacistOnlinePreferenceKey = 'pharmacist_online';

  final String _apiUrl = baseUrl;
  final List<Map<String, dynamic>> _incomingRequests = [];
  final List<Map<String, dynamic>> _onlinePharmacists = [];

  io.Socket? _socket;
  bool _isOnline = false;
  bool _isSocketConnected = false;
  bool _isConnecting = true;
  bool _hasPharmacistAccess = false;
  bool _isUpdatingAvailability = false;

  @override
  void initState() {
    super.initState();
    _connectSocket();
  }

  Future<void> _connectSocket() async {
    if (mounted) {
      setState(() {
        _isConnecting = true;
      });
    }

    final token = await _getPharmacistAuthToken();
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _isOnline = false;
        _hasPharmacistAccess = false;
      });
      _showNotification(
        'Authentication failed',
        'Please sign in again to access pharmacist tools.',
        isError: true,
      );
      return;
    }

    final canUsePharmacistTools = await _verifyPharmacistAccess(token);
    if (!canUsePharmacistTools) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _isOnline = false;
        _hasPharmacistAccess = false;
      });
      _showNotification(
        'Pharmacist access required',
        'Only approved pharmacists can claim and reply to customer consultations.',
        isError: true,
      );
      return;
    }

    if (mounted) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _hasPharmacistAccess = true;
        _isOnline = prefs.getBool(_pharmacistOnlinePreferenceKey) ?? false;
      });
    }
    await _loadQueueFromRest(token);
    await _loadOnlinePharmacists(token);

    _socket?.dispose();
    _socket = io.io(
      _apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      if (!mounted) return;
      setState(() {
        _isSocketConnected = true;
        _isConnecting = false;
      });
      _emitAvailability(_isOnline);
      _loadQueueFromRest(token);
      _loadOnlinePharmacists(token);
    });

    _socket!.on('incoming_chat_request', (data) {
      if (!_isOnline) return;
      _upsertIncomingRequest(data);

      _showNotification(
        'New consultation request',
        (data['textPreview'] ?? 'A customer is waiting for pharmacist support.')
            .toString(),
      );
    });

    _socket!.on('pharmacistStatus', (data) {
      if (data is! Map || !mounted) return;
      final pharmacists = data['pharmacists'];
      setState(() {
        _onlinePharmacists
          ..clear()
          ..addAll(
            pharmacists is List
                ? pharmacists.whereType<Map>().map((item) {
                    return {
                      'id': (item['id'] ?? '').toString(),
                      'name': (item['name'] ?? 'Pharmacist').toString(),
                      'phoneNumber': (item['phoneNumber'] ?? '').toString(),
                    };
                  }).toList()
                : const [],
          );
      });
    });

    _socket!.onDisconnect((_) {
      if (!mounted) return;
      setState(() {
        _isSocketConnected = false;
        _isConnecting = false;
      });
    });

    _socket!.onConnectError((err) {
      debugPrint('Pharmacist socket connect error: $err');
      if (!mounted) return;
      setState(() {
        _isSocketConnected = false;
        _isConnecting = false;
      });
      _showNotification(
        'Connection issue',
        'Could not connect to live pharmacist chat. Pull to refresh or try again.',
        isError: true,
      );
    });

    _socket!.onError((err) {
      debugPrint('Pharmacist socket error: $err');
      if (!mounted) return;
      setState(() {
        _isSocketConnected = false;
        _isConnecting = false;
      });
    });
  }

  Map<String, dynamic> _ackPayload(dynamic response) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    return <String, dynamic>{};
  }

  void _emitAvailability(bool online) {
    _socket?.emitWithAck(
      'pharmacist_status_update',
      {'online': online},
      ack: (response) {
        final data = _ackPayload(response);
        if (data['success'] != true) {
          debugPrint('Pharmacist availability socket update failed: $data');
        }
      },
    );
  }

  Future<void> _setOnline(bool online) async {
    if (!_hasPharmacistAccess || _isUpdatingAvailability) return;

    final previous = _isOnline;
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isOnline = online;
        _isUpdatingAvailability = true;
      });
    }
    await prefs.setBool(_pharmacistOnlinePreferenceKey, online);
    _emitAvailability(online);

    try {
      final token = await _getPharmacistAuthToken();
      if (token == null) throw Exception('Missing token');
      final response = await http.put(
        Uri.parse('$_apiUrl/api/chat/pharmacist/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'online': online}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Status ${response.statusCode}');
      }
      if (online) {
        _showNotification(
          'You are online',
          'Patients can now reach you. This status stays on until you turn it off.',
        );
      }
      await _loadOnlinePharmacists(token);
    } catch (error) {
      await prefs.setBool(_pharmacistOnlinePreferenceKey, previous);
      _emitAvailability(previous);
      if (mounted) {
        setState(() => _isOnline = previous);
      }
      _showNotification(
        'Status update failed',
        'Could not update pharmacist availability. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  void _upsertIncomingRequest(dynamic data) {
    if (data is! Map) return;

    final String sessionId = (data['sessionId'] ?? '').toString();
    if (sessionId.isEmpty) return;

    final request = {
      'sessionId': sessionId,
      'userId': (data['userId'] ?? '').toString(),
      'textPreview': (data['textPreview'] ?? 'No preview available.')
          .toString(),
      'createdAt': data['createdAt'] != null
          ? DateTime.tryParse(data['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    };

    if (!mounted) return;
    setState(() {
      _incomingRequests.removeWhere((req) => req['sessionId'] == sessionId);
      _incomingRequests.insert(0, request);
    });
  }

  Future<void> _loadQueueFromRest(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/api/chat/pharmacist/queue'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final queue = data['queue'];
      if (queue is! List || !mounted) return;

      setState(() {
        _incomingRequests
          ..clear()
          ..addAll(
            queue
                .whereType<Map>()
                .map((item) {
                  return {
                    'sessionId': (item['sessionId'] ?? '').toString(),
                    'userId': (item['userId'] ?? '').toString(),
                    'textPreview':
                        (item['textPreview'] ?? 'No preview available.')
                            .toString(),
                    'createdAt': item['createdAt'] != null
                        ? DateTime.tryParse(item['createdAt'].toString()) ??
                              DateTime.now()
                        : DateTime.now(),
                  };
                })
                .where((item) => item['sessionId'].toString().isNotEmpty),
          );
      });
    } catch (e) {
      debugPrint('Queue refresh failed: $e');
    }
  }

  Future<void> _loadOnlinePharmacists(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiUrl/api/chat/pharmacists/online'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pharmacists = data['pharmacists'];
      if (pharmacists is! List || !mounted) return;
      setState(() {
        _onlinePharmacists
          ..clear()
          ..addAll(
            pharmacists.whereType<Map>().map((item) {
              return {
                'id': (item['id'] ?? '').toString(),
                'name': (item['name'] ?? 'Pharmacist').toString(),
                'phoneNumber': (item['phoneNumber'] ?? '').toString(),
              };
            }),
          );
      });
    } catch (e) {
      debugPrint('Online pharmacists refresh failed: $e');
    }
  }

  Future<bool> _verifyPharmacistAccess(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final role = data['role']?.toString().toLowerCase().trim();
      final pharmacistStatus = data['pharmacistStatus']
          ?.toString()
          .toLowerCase()
          .trim();

      return data['isPharmacist'] == true ||
          role == 'pharmacist' ||
          pharmacistStatus == 'approved';
    } catch (e) {
      debugPrint('Pharmacist access verification failed: $e');
      return false;
    }
  }

  Future<void> _refreshDashboard() async {
    final token = await _getPharmacistAuthToken();
    if (token != null) {
      await _loadQueueFromRest(token);
      await _loadOnlinePharmacists(token);
    }

    if (_socket?.connected != true) {
      await _connectSocket();
    } else if (mounted) {
      setState(() {});
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  Future<void> _claimSession(String sessionId) async {
    if (!_hasPharmacistAccess) {
      _showNotification(
        'Pharmacist access required',
        'Only approved pharmacists can claim customer consultations.',
        isError: true,
      );
      return;
    }

    if (!_isOnline || _socket == null) {
      await _claimSessionViaRest(sessionId);
      return;
    }

    _socket!.emitWithAck(
      'pharmacist_claim_session',
      {'sessionId': sessionId},
      ack: (response) {
        final data = _ackPayload(response);

        if (data['success'] == true) {
          if (!mounted) return;
          setState(() {
            _incomingRequests.removeWhere(
              (req) => req['sessionId'] == sessionId,
            );
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Consultation claimed successfully.')),
          );

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(sessionId: sessionId, isPharmacistView: true),
            ),
          );
        } else {
          final message =
              (data['message'] ??
                      'This consultation may already be assigned to another pharmacist.')
                  .toString();

          _showNotification('Claim failed', message, isError: true);

          if (message.contains('already claimed') && mounted) {
            setState(() {
              _incomingRequests.removeWhere(
                (req) => req['sessionId'] == sessionId,
              );
            });
          }
        }
      },
    );
  }

  Future<void> _claimSessionViaRest(String sessionId) async {
    try {
      final token = await _getPharmacistAuthToken();
      if (token == null) {
        throw Exception('Missing token');
      }

      final response = await http.post(
        Uri.parse('$_apiUrl/api/chat/pharmacist/claim/$sessionId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;
        setState(() {
          _incomingRequests.removeWhere((req) => req['sessionId'] == sessionId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consultation claimed successfully.')),
        );
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                ChatScreen(sessionId: sessionId, isPharmacistView: true),
          ),
        );
        return;
      }

      throw Exception(data['message'] ?? 'Claim failed');
    } catch (e) {
      _showNotification('Claim failed', e.toString(), isError: true);
    }
  }

  void _showNotification(String title, String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title: $message'),
        backgroundColor: isError ? PharmacyUi.danger : PharmacyUi.deepNavy,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  String _formatReceivedTime(DateTime value) {
    final now = DateTime.now();
    final difference = now.difference(value);

    if (difference.inMinutes < 1) {
      return 'Just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} hr ago';
    }
    return DateFormat('MMM d, h:mm a').format(value);
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _isConnecting
        ? 'Connecting'
        : _isOnline
        ? 'Online'
        : 'Offline';
    final statusColor = _isConnecting
        ? PharmacyUi.warning
        : _isOnline
        ? PharmacyUi.success
        : PharmacyUi.danger;

    if (!_isConnecting && !_hasPharmacistAccess) {
      return Theme(
        data: PharmacyUi.theme,
        child: Scaffold(
          appBar: AppBar(title: const Text('Pharmacist Workspace')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: PharmacyPanel(
                title: 'Pharmacist access required',
                subtitle:
                    'Only approved pharmacists can claim customer consultations and send replies.',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 56,
                      color: PharmacyUi.deepNavy.withValues(alpha: 0.45),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Ask an admin to approve your pharmacist verification before using this workspace.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PharmacyUi.mutedText,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _connectSocket,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Check Again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: PharmacyUi.theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pharmacist Workspace'),
          actions: [
            IconButton(
              tooltip: 'Reconnect',
              onPressed: _connectSocket,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshDashboard,
          color: PharmacyUi.deepNavy,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            children: [
              PharmacyHero(
                badge: 'Healthcare operations',
                title: 'Pharmacy dashboard',
                subtitle:
                    'Manage incoming consultation demand, stay ready for live claims, and move patients into the right support flow fast.',
                icon: Icons.local_pharmacy_rounded,
                stats: [
                  PharmacyStat(
                    label: 'Queue size',
                    value: '${_incomingRequests.length}',
                  ),
                  PharmacyStat(label: 'Connection', value: statusLabel),
                  PharmacyStat(
                    label: 'Mode',
                    value: _isOnline ? 'Accepting consults' : 'Offline',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              PharmacyPanel(
                title: 'Readiness status',
                subtitle:
                    'Keep your consultation workspace available so patients can reach an approved pharmacist quickly.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 52,
                          width: 52,
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            _isOnline
                                ? Icons.health_and_safety_outlined
                                : Icons.portable_wifi_off_outlined,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isOnline
                                    ? 'You are visible to patients and admin. Turn this off when you stop taking consultations.'
                                    : _isSocketConnected
                                    ? 'You are connected but offline. Turn online to receive consultation requests.'
                                    : 'Reconnect, then turn online to receive live pharmacy consultations.',
                                style: const TextStyle(
                                  color: PharmacyUi.mutedText,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isUpdatingAvailability)
                          const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Switch(
                            value: _isOnline,
                            onChanged: _hasPharmacistAccess
                                ? (value) => _setOnline(value)
                                : null,
                          ),
                      ],
                    ),
                    if (_isOnline) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: PharmacyUi.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: PharmacyUi.success.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Text(
                          'Online notification is active. It stays here until you switch offline.',
                          style: TextStyle(
                            color: PharmacyUi.deepNavy,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              PharmacyPanel(
                title: 'Online pharmacists',
                subtitle:
                    'Approved pharmacists currently available for live consultation assignment.',
                child: _onlinePharmacists.isEmpty
                    ? const Text(
                        'No pharmacist is online right now.',
                        style: TextStyle(color: PharmacyUi.mutedText),
                      )
                    : Column(
                        children: [
                          for (
                            var i = 0;
                            i < _onlinePharmacists.length;
                            i++
                          ) ...[
                            _buildOnlinePharmacistTile(_onlinePharmacists[i]),
                            if (i != _onlinePharmacists.length - 1)
                              const Divider(height: 18),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              PharmacyPanel(
                title: 'Pending consultation requests',
                subtitle:
                    'New pharmacy support sessions appear here the moment they are escalated.',
                child: _incomingRequests.isEmpty
                    ? Column(
                        children: [
                          Icon(
                            Icons.mark_email_read_outlined,
                            size: 72,
                            color: PharmacyUi.deepNavy.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'No active requests right now.',
                            style: TextStyle(
                              color: PharmacyUi.deepNavy,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Stay connected and new patient escalations will appear here automatically.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: PharmacyUi.mutedText,
                              height: 1.5,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          for (
                            var i = 0;
                            i < _incomingRequests.length;
                            i++
                          ) ...[
                            _buildRequestCard(_incomingRequests[i]),
                            if (i != _incomingRequests.length - 1)
                              const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              PharmacyPanel(
                title: 'Care handling reminders',
                subtitle:
                    'A few operational habits help consultations feel safe, fast, and trustworthy.',
                child: const Column(
                  children: [
                    _PharmacyReminder(
                      icon: Icons.medication_outlined,
                      text:
                          'Clarify dosage concerns and check for allergy or interaction risks before recommending next steps.',
                    ),
                    SizedBox(height: 12),
                    _PharmacyReminder(
                      icon: Icons.schedule_outlined,
                      text:
                          'Claim only the sessions you can actively manage so patients do not wait in a silent consultation.',
                    ),
                    SizedBox(height: 12),
                    _PharmacyReminder(
                      icon: Icons.fact_check_outlined,
                      text:
                          'Keep answers concise, professional, and action-focused throughout each consultation.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOnlinePharmacistTile(Map<String, dynamic> pharmacist) {
    final name = pharmacist['name']?.toString() ?? 'Pharmacist';
    final phone = pharmacist['phoneNumber']?.toString() ?? '';

    return Row(
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: PharmacyUi.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.local_pharmacy_outlined,
            color: PharmacyUi.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: PharmacyUi.deepNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (phone.isNotEmpty)
                Text(
                  phone,
                  style: const TextStyle(
                    color: PharmacyUi.mutedText,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        const Text(
          'Online',
          style: TextStyle(
            color: PharmacyUi.success,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final userId = (request['userId'] as String?) ?? '';
    final preview =
        (request['textPreview'] as String?) ?? 'No preview available.';
    final createdAt = request['createdAt'] as DateTime? ?? DateTime.now();
    final sessionId = (request['sessionId'] as String?) ?? '';

    final shortUserId = userId.length > 8
        ? '${userId.substring(0, 8)}...'
        : userId;
    final shortSessionId = sessionId.length > 8
        ? '${sessionId.substring(0, 8)}...'
        : sessionId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PharmacyUi.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PharmacyUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: PharmacyUi.deepNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: PharmacyUi.deepNavy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shortUserId.isEmpty
                          ? 'Patient session'
                          : 'Patient $shortUserId',
                      style: const TextStyle(
                        color: PharmacyUi.deepNavy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Session $shortSessionId',
                      style: const TextStyle(
                        color: PharmacyUi.mutedText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: PharmacyUi.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatReceivedTime(createdAt),
                  style: const TextStyle(
                    color: PharmacyUi.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            preview,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PharmacyUi.deepNavy, height: 1.45),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showNotification('Request preview', preview);
                  },
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _claimSession(sessionId),
                  icon: const Icon(Icons.medical_services_outlined),
                  label: const Text('Claim'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PharmacyReminder extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PharmacyReminder({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: PharmacyUi.deepNavy.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: PharmacyUi.deepNavy, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: PharmacyUi.deepNavy, height: 1.45),
          ),
        ),
      ],
    );
  }
}
