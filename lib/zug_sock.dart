import 'dart:ui';

import 'package:lichess_package/lichess_package.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ZugSock {
  late final WebSocketChannel _channel;
  VoidCallback onClose;

  ZugSock(String address,VoidCallback onConnect,SockMsgCallback onMsg,this.onClose) {

    _channel = WebSocketChannel.connect(
      Uri.parse(address),
    );

    _channel.ready.then((val) {
      logMsg("Listening...");
      _channel.stream.listen((message) {
        onMsg(message);
      }, onDone: () {
        logMsg("Websocket Closed"); close();
      }, onError: (error) {
        logMsg("Websocket Error: ${error.toString()}"); close();
      });
      onConnect();
    }).onError((error, stackTrace) {
      logMsg("Websocket connection error: ${error.toString()}");
      logMsg(stackTrace.toString()); close();
    });
  }

  void send(msg) {
    if ((_channel.closeCode ?? 0) > 0) { logMsg("Closed socket!");
    close();
    }
    else {
      _channel.sink.add(msg);
    }
  }

  void close() {
    _channel.sink.close();
    onClose();
  }

  void logMsg(String msg) {
    print(msg);
  }

}
