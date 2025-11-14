library zug_net;

import 'dart:ui';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef SockMsgCallback = void Function(dynamic msg);

class ZugSock {
  late final WebSocketChannel _channel;
  VoidCallback onClose;

  ZugSock(String address, VoidCallback onConnect, SockMsgCallback onMsg, this.onClose, {int pingInterval = 30}) {

    _channel = IOWebSocketChannel.connect(
      address,
      pingInterval: Duration(seconds: pingInterval),
    );

    _channel.stream.listen(
          (message) {
        logMsg("RECV: $message");
        onMsg(message);
      },
      onDone: () {
        logMsg("WebSocket Closed");
        logMsg("  closeCode   = ${_channel.closeCode}");
        logMsg("  closeReason = ${_channel.closeReason}");
        close();
      },
      onError: (error) {
        logMsg("WebSocket Error: $error");
        close();
      },
    );

    onConnect();
  }

  void send(msg) {
    if ((_channel.closeCode ?? 0) > 0) {
      logMsg("Closed socket!");
      close();
    } else {
      _channel.sink.add(msg);
    }
  }

  void close() {
    _channel.sink.close();
    onClose();
  }

  void logMsg(String msg) => print(msg);
}

