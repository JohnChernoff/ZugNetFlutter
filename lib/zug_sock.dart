library zug_net;

import 'dart:ui';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SockMsgCallback = void Function(dynamic msg);

class ZugSock {
  late final WebSocketChannel _channel;
  VoidCallback onClose;

  ZugSock(
      String address,
      VoidCallback onConnect,
      SockMsgCallback onMsg,
      this.onClose,
      ) {
    _channel = WebSocketChannel.connect(Uri.parse(address));

    // Extract underlying browser WebSocket
    final ws = (_channel as dynamic).innerWebSocket;

    if (ws != null) {
      ws.onClose.listen((event) {
        print("Browser close event:");
        print("  code: ${event.code}");
        print("  reason: ${event.reason}");
        print("  clean: ${event.wasClean}");
      });
    }

    // Listen for actual messages
    _channel.stream.listen(
          (message) {
        //print("WebSocket message: $message");
        onMsg(message);
      },
      onDone: () {
        print("WebSocket done");
        close();
      },
      onError: (error) {
        print("WebSocket error: $error");
        close();
      },
    );

    onConnect();
  }

  void send(msg) => _channel.sink.add(msg);

  void close() {
    _channel.sink.close();
    onClose();
  }
}

