import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static final WebSocketService instance = WebSocketService._internal();
  WebSocketService._internal();

  WebSocketChannel? _channel;
  
  // A permanent, non-nullable controller that will NEVER drop listeners
  final StreamController<dynamic> _streamController = StreamController<dynamic>.broadcast();

  // Cached connection details for auto-reconnect
  String? _lastRoomCode;
  String? _lastPlayerName;
  String? _lastIpAddress;
  bool _isConnected = false;
  bool _isExplicitlyDisconnected = false;

  // Screens will listen to this safe broadcast stream safely
  Stream<dynamic> get stream => _streamController.stream;

  void connect(String roomCode, String playerName, String ipAddress) {
    _lastRoomCode = roomCode;
    _lastPlayerName = playerName;
    _lastIpAddress = ipAddress;
    _isExplicitlyDisconnected = false;
    _initConnection();
  }

  void _initConnection() {
    if (_isExplicitlyDisconnected) return;
    if (_lastRoomCode == null || _lastPlayerName == null || _lastIpAddress == null) return;
    if (_channel != null) {
      if (_isConnected) return;
      try {
        _channel?.sink.close();
      } catch (_) {}
      _channel = null;
    }

    String scheme = 'wss';
    String address = _lastIpAddress!;
    
    if (address.startsWith('ws://')) {
      scheme = 'ws';
      address = address.replaceFirst('ws://', '');
    } else if (address.startsWith('wss://')) {
      scheme = 'wss';
      address = address.replaceFirst('wss://', '');
    } else if (address.contains('localhost') || 
               address.contains('127.0.0.1') || 
               address.contains('10.0.2.2') || 
               address.contains('192.168.') || 
               address.contains(':')) {
      scheme = 'ws';
    }
    
    final wsUrl = Uri.parse('$scheme://$address/ws/$_lastRoomCode/$_lastPlayerName');
    try {
      _channel = WebSocketChannel.connect(wsUrl);
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          debugPrint("SERVER RAW: $message"); 
          if (!_streamController.isClosed) {
            _streamController.add(message);
          }
        },
        onDone: () {
          if (_isExplicitlyDisconnected) {
            debugPrint("WebSocket Connection Closed Explicitly.");
            return;
          }
          debugPrint("WebSocket Connection Dropped. Reconnecting...");
          _channel = null;
          _isConnected = false;
          // Auto-reconnect after 2 seconds if the phone drops it
          Future.delayed(const Duration(seconds: 2), _initConnection);
        },
        onError: (error) {
          debugPrint("WebSocket Error: $error");
          _isConnected = false;
          _channel = null;
        }
      );
      
      debugPrint("Connected to Game Server at $wsUrl");
    } catch (e) {
      debugPrint("WebSocket connection failed: $e");
      _isConnected = false;
    }
  }

  void sendAction(Map<String, dynamic> actionData) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode(actionData));
      debugPrint("SENT TO SERVER: $actionData");
    } else {
      debugPrint("FAILED TO SEND: Socket is disconnected. Waiting for auto-reconnect.");
    }
  }

  void disconnect() {
    _isExplicitlyDisconnected = true;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}