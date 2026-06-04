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

  // Screens will listen to this safe broadcast stream safely
  Stream<dynamic> get stream => _streamController.stream;

  void connect(String roomCode, String playerName, String ipAddress) {
    _lastRoomCode = roomCode;
    _lastPlayerName = playerName;
    _lastIpAddress = ipAddress;
    _initConnection();
  }

  void _initConnection() {
    if (_lastRoomCode == null || _lastPlayerName == null || _lastIpAddress == null) return;
    if (_channel != null) return; // Prevent double connections

    
    final wsUrl = Uri.parse('wss://$_lastIpAddress/ws/$_lastRoomCode/$_lastPlayerName');
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
          debugPrint("WebSocket Connection Dropped. Reconnecting...");
          _channel = null;
          _isConnected = false;
          // Auto-reconnect after 2 seconds if the phone drops it
          Future.delayed(const Duration(seconds: 2), _initConnection);
        },
        onError: (error) {
          debugPrint("WebSocket Error: $error");
          _isConnected = false;
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
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
}