library lichess_package;

import 'dart:async';
import 'dart:convert';
import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;
import 'package:fetch_client/fetch_client.dart' as fetch;

enum LichessVariant {
  standard, chess960, crazyhouse, antichess, atomic, horde, kingOfTheHill, racingKings, threeCheck, fromPosition
}

enum BoardAction {
  resign,abort,drawYes,drawNo,offerTakeBack,declineTakeBack,claimVictory,beserk
}

typedef EventStreamCallback = void Function(Stream<String> stream);
typedef GameStreamCallback = void Function(String id, Stream<String> stream);

class Lichess {

  static http.Client? seekClient;
  static Completer<http.Response>? seekCompleter;

  static Future<int> makeMove(String move, String gameId, String token, {web = false}) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    return (await client.post(Uri.parse("https://lichess.org/api/board/game/$gameId/move/$move"),
        headers: {
          'Content-type' : 'application/x-www-form-urlencoded',
          'Authorization' : "Bearer $token",
        }
    )).statusCode;
  }

  static Future<int> boardAction(BoardAction action, String gameID, String token, {web = false}) async {
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
    return (await client.post(Uri.parse("https://lichess.org/api/board/game/$gameID/$actionPath"),
        headers: {
          'Content-type' : 'application/x-www-form-urlencoded',
          'Authorization' : "Bearer $token",
        }
    )).statusCode;
  }

  static Future<dynamic> getAccount(String oauth,{bool web = false}) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    final url = Uri(scheme: "https", host: "lichess.org", path: '/api/account');
    return jsonDecode((await client.get(url,headers: {
      'Content-type' : 'application/json',
      'Authorization' : "Bearer $oauth",
    })).body);
  }

  static Future<String> createSeek(LichessVariant variant, int minutes, int inc, bool rated, String oauth, {bool web = false, minRating = 0, maxRating = 9999, String? color}) async {
    removeSeek();
    seekCompleter = Completer();
    seekClient = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    final url = Uri(scheme: "https", host: "lichess.org", path: '/api/board/seek');
    String seekParams = "variant=${variant.name}&rated=$rated&time=$minutes&color=${color ?? 'random'}&increment=$inc&ratingRange=$minRating-$maxRating"; //print("Seek params: $bodyText");
    seekClient!.post(url,headers: {
      'Content-type' : 'application/x-ndjson',
      'Authorization' : "Bearer $oauth",
    }, body: seekParams).then((response) { //print("Got seek response: ${response.body}");
      seekCompleter?.complete(response);
    });
    http.Response? response = await seekCompleter?.future;
    seekCompleter = null;
    return "${response?.body} / ${response?.statusCode}";
  }

  static void removeSeek() {
    seekClient?.close();
    seekClient = null;
    seekCompleter?.complete(http.Response("Seek cancelled",200));
  }

  static void getEventStream(String token, EventStreamCallback callback, {bool web = false}) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    final url = Uri.parse('https://lichess.org/api/stream/event');
    final request = http.Request('GET', url);
    request.headers['Content-type'] = 'application/x-ndjson';
    request.headers['Authorization'] = "Bearer $token";
    client.send(request).then((response) => callback(response.stream.toStringStream()));
  }

  static void followGame(String id, String token, GameStreamCallback callback, { bool web = false }) async {
    final client = web ? fetch.FetchClient(mode: RequestMode.cors) : http.Client();
    final url = Uri.parse('https://lichess.org/api/board/game/stream/$id');
    final request = http.Request('GET', url);
    request.headers['Content-type'] = 'application/x-ndjson';
    request.headers['Accept'] = 'application/x-ndjson';
    request.headers['Authorization'] =  "Bearer $token";
    client.send(request).then((response) => callback(id,response.stream.toStringStream()));
  }

  static Future<List<dynamic>> getTV(String channel, int numGames) async {
    List<dynamic> games = [];
    final client = http.Client();
    Map<String,String> headers = {};
    headers['Accept'] = 'application/x-ndjson';
    http.Response response = await client.get(Uri.parse("https://lichess.org/api/tv/$channel?nb=$numGames"),headers: headers);
    response.body.split("\n").forEach((game) { //print("Game: $game");
        if (game.isNotEmpty) games.add(jsonDecode(game));
    });
    return games;
  }
}
