library zug_net;

import 'dart:ui';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SockMsgCallback = void Function(dynamic msg);

class ZugSock {
  static ZugSock? _instance;

  late final WebSocketChannel _channel;
  VoidCallback onClose;
  bool _isConnected = false;
  bool _isConnecting = false;

  // Private constructor for singleton pattern
  ZugSock._internal(String address, VoidCallback onConnect, SockMsgCallback onMsg, this.onClose) {
    _connect(address, onConnect, onMsg);
  }

  // Factory constructor - ensures only one instance
  factory ZugSock(String address, VoidCallback onConnect, SockMsgCallback onMsg, VoidCallback onClose) {
    _instance?.close();
    _instance = ZugSock._internal(address, onConnect, onMsg, onClose);
    return _instance!;
  }

  void _connect(String address, VoidCallback onConnect, SockMsgCallback onMsg) {
    if (_isConnecting || _isConnected) {
      logMsg("Already connecting or connected");
      return;
    }

    _isConnecting = true;
    logMsg("Connecting to $address");

    _channel = WebSocketChannel.connect(
      Uri.parse(address),
    );

    _channel.ready.then((val) {
      _isConnecting = false;
      _isConnected = true;
      logMsg("WebSocket connected and listening...");

      _channel.stream.listen(
            (message) {
          if (_isConnected) {
            onMsg(message);
          }
        },
        onDone: () {
          logMsg("WebSocket stream closed");
          _isConnected = false;
          close();
        },
        onError: (error) {
          logMsg("WebSocket error: ${error.toString()}");
          _isConnected = false;
          close();
        },
        cancelOnError: true,
      );

      onConnect();
    }).onError((error, stackTrace) {
      _isConnecting = false;
      _isConnected = false;
      logMsg("WebSocket connection error: ${error.toString()}");
      logMsg(stackTrace.toString());
      close();
    });
  }

  void send(msg) {
    if (!_isConnected || (_channel.closeCode ?? 0) > 0) {
      logMsg("Cannot send - connection closed!");
      close();
      return;
    }

    try {
      _channel.sink.add(msg);
    } catch (e) {
      logMsg("Error sending message: $e");
      close();
    }
  }

  void close() {
    if (!_isConnected && !_isConnecting) {
      return; // Already closed
    }

    _isConnected = false;
    _isConnecting = false;

    try {
      _channel.sink.close();
    } catch (e) {
      logMsg("Error closing sink: $e");
    }

    onClose();
  }

  void logMsg(String msg) {
    print("[ZugSock] $msg");
  }
}
