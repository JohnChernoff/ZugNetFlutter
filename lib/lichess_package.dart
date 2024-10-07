library lichess_package;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui';
import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;
import 'package:fetch_client/fetch_client.dart' as fetch;
import 'package:lichess_package/zug_sock.dart';

enum LichessVariant {
  standard, chess960, crazyhouse, antichess, atomic, horde, kingOfTheHill, racingKings, threeCheck, fromPosition
}

enum BoardAction {
  resign,abort,drawYes,drawNo,offerTakeBack,declineTakeBack,claimVictory,beserk
}

enum LichessRatingType {
  ultraBullet,bullet,blitz,rapid,classical
}

typedef SockMsgCallback = void Function(dynamic msg);
typedef EventStreamCallback = void Function(Stream<String> stream);
typedef GameStreamCallback = void Function(String id, Stream<String> stream);

class LichessClient {

  String schema;
  String host;
  bool web;
  bool running = true;
  Queue sockMsgQueue = Queue();
  late ZugSock lichSock;

  Uri getEndPoint(String path, {Map<String, dynamic>? params}) {
    return Uri(scheme: schema, host: host, path: path, queryParameters: params);
  }

  http.Client? seekClient;
  Completer<http.Response>? seekCompleter;

  LichessClient({this.schema = "https", this.host = "lichess.org", this.web = false, VoidCallback? onConnect, VoidCallback? onDisconnect, SockMsgCallback? onMsg}) {
    lichSock = ZugSock('wss://socket.$host/api/socket', onConnect ?? defConnect, onMsg ?? defMsg, onDisconnect ?? defDisconnect);
    loopSock();
  }

  void defConnect() {}
  void defDisconnect() {}
  void defMsg(msg) {}

  Future<void> loopSock() async {
    while (running) {
      if (sockMsgQueue.isNotEmpty) {
        lichSock.send(jsonEncode(sockMsgQueue.removeLast()));
      }
      await Future.delayed(const Duration(seconds: 2));
      lichSock.send("{ t : 0, p : 0 }");
    }
  }

  void addSockMsg(msg) {
    sockMsgQueue.addFirst(msg);
  }

  static LichessRatingType? getRatingType(double minutes, int inc) {
    int t = (40 * inc) + ((minutes * 60).round());
    return switch(t) {
      < 29 => LichessRatingType.ultraBullet,
      < 179 => LichessRatingType.bullet,
      < 479 => LichessRatingType.blitz,
      < 1499 => LichessRatingType.rapid,
      >= 1500 => LichessRatingType.classical,
      _ => null}; //throw Exception("weird time control")};
  }

  Future<int> makeMove(String move, String gameId, String token) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    return (await client.post(getEndPoint("api/board/game/$gameId/move/$move"),
        headers: {
          'Content-type' : 'application/x-www-form-urlencoded',
          'Authorization' : "Bearer $token",
        }
    )).statusCode;
  }

  Future<int> boardAction(BoardAction action, String gameID, String token) async {
    String actionPath = switch(action) {
      BoardAction.resign => "resign",
      BoardAction.abort => "abort",
      BoardAction.drawYes => "draw/yes",
      BoardAction.drawNo => "draw/no",
      BoardAction.offerTakeBack => "takeback/yes",
      BoardAction.declineTakeBack => "takeback/yes",
      BoardAction.claimVictory => "claim-victory",
      BoardAction.beserk => "berserk",
    };
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    return (await client.post(getEndPoint("api/board/game/$gameID/$actionPath"),
        headers: {
          'Content-type' : 'application/x-www-form-urlencoded',
          'Authorization' : "Bearer $token",
        }
    )).statusCode;
  }

  Future<dynamic> getAccount(String oauth) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    return jsonDecode((await client.get(getEndPoint('api/account'),headers: {
      'Content-type' : 'application/json',
      'Authorization' : "Bearer $oauth",
    })).body);
  }

  Future<String> createSeek(LichessVariant variant, int minutes, int inc, bool rated, String oauth, {int? minRating, int? maxRating, String? color}) async {
    removeSeek();
    seekCompleter = Completer();
    seekClient = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    String ratRange = minRating != null && maxRating != null ? "&ratingRange=$minRating-$maxRating" : "";
    String seekParams = "variant=${variant.name}&rated=$rated&time=$minutes&color=${color ?? 'random'}&increment=$inc$ratRange"; //print("Seek params: $bodyText");
    seekClient!.post(getEndPoint('api/board/seek'),headers: {
      'Content-type' : 'application/x-www-form-urlencoded',
      'Authorization' : "Bearer $oauth",
    }, body: seekParams).then((response) { //print("Got seek response: ${response.body}");
      seekCompleter?.complete(response);
    });
    http.Response? response = await seekCompleter?.future;
    seekCompleter = null;
    return "${response?.body} / ${response?.statusCode}";
  }

  void removeSeek() {
    seekClient?.close();
    seekClient = null;
    seekCompleter?.complete(http.Response("Seek cancelled",200));
  }

  void getEventStream(String token, EventStreamCallback callback) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    final request = http.Request('GET', getEndPoint("api/stream/event"));
    request.headers['Content-type'] = 'application/x-ndjson';
    request.headers['Authorization'] = "Bearer $token";
    client.send(request).then((response) => callback(response.stream.toStringStream()));
  }

  void followGame(String id, String token, GameStreamCallback callback) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    final request = http.Request('GET', getEndPoint("api/board/game/stream/$id"));
    request.headers['Content-type'] = 'application/x-ndjson';
    request.headers['Accept'] = 'application/x-ndjson';
    request.headers['Authorization'] =  "Bearer $token";
    client.send(request).then((response) => callback(id,response.stream.toStringStream()));
  }

  Future<List<dynamic>> getTV(String channel, int numGames) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    List<dynamic> games = [];
    Map<String,String> headers = {};
    headers['Accept'] = 'application/x-ndjson';
    http.Response response = await client.get(getEndPoint("api/tv/$channel",params : {'nb' : "$numGames"}),headers: headers);
    response.body.split("\n").forEach((game) { //print("Game: $game");
        if (game.isNotEmpty) games.add(jsonDecode(game));
    });
    return games;
  }
}
