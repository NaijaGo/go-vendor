// lib/services/socket_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class SocketService {
  io.Socket? socket;
  static DateTime? _lastConnectAttempt;
  static DateTime? _lastErrorLogAt;
  static DateTime? _hostLookupBackoffUntil;

  bool get isConnected => socket?.connected ?? false;

  Future<void> connect(String baseUrl) async {
    final now = DateTime.now();
    final hostLookupBackoffUntil = _hostLookupBackoffUntil;
    if (hostLookupBackoffUntil != null &&
        now.isBefore(hostLookupBackoffUntil)) {
      return;
    }

    final lastAttempt = _lastConnectAttempt;
    if (lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(minutes: 1)) {
      return;
    }
    _lastConnectAttempt = now;

    if (socket != null) {
      if (!isConnected) {
        socket!.connect();
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';

    socket = io.io(baseUrl, <String, dynamic>{
      'transports': ['websocket', 'polling'],
      'autoConnect': false,
      'auth': {'token': token},
      'forceNew': false,
      'timeout': 10000,
      'reconnection': true,
      'reconnectionAttempts': 2,
      'reconnectionDelay': 10000,
      'reconnectionDelayMax': 60000,
    });

    socket!.connect();

    socket!.onConnect((_) {
      debugPrint('Socket connected');
    });

    socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
    });

    socket!.onConnectError(_logConnectError);
  }

  void joinDispute(String disputeId) {
    socket?.emit('joinDispute', disputeId);
  }

  void leaveDispute(String disputeId) {
    socket?.emit('leaveDispute', disputeId);
  }

  void sendMessage(String disputeId, String text, List<String> attachments) {
    socket?.emit('sendMessage', {
      'disputeId': disputeId,
      'text': text,
      'attachments': attachments,
    });
  }

  void onMessage(void Function(dynamic) cb) {
    socket?.on('message', cb);
  }

  void on(String event, void Function(dynamic) cb) {
    socket?.on(event, cb);
  }

  void off(String event) {
    socket?.off(event);
  }

  void onConnect(void Function(dynamic) cb) {
    socket?.onConnect(cb);
  }

  void onDisconnect(void Function(dynamic) cb) {
    socket?.onDisconnect(cb);
  }

  void joinOrderTracking(String orderId) {
    socket?.emit('join_order_tracking', {'orderId': orderId});
  }

  void leaveOrderTracking(String orderId) {
    socket?.emit('leave_order_tracking', {'orderId': orderId});
  }

  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }

  void _logConnectError(dynamic err) {
    final message = err.toString();
    final now = DateTime.now();
    if (message.contains('Failed host lookup') ||
        message.contains('No address associated with hostname')) {
      _hostLookupBackoffUntil = now.add(const Duration(minutes: 5));
      socket?.disconnect();
    }

    final lastLog = _lastErrorLogAt;
    if (lastLog != null &&
        now.difference(lastLog) < const Duration(minutes: 2)) {
      return;
    }
    _lastErrorLogAt = now;
    debugPrint('Socket connect error: $message');
  }
}
