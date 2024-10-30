import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';

class OauthClient {
  static WebViewController webViewController = WebViewController();
  static const String _charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  static const String localAndroidHost = "10.0.2.2";
  static const String localIOSHost = "127.0.0.1";
  String authPath, tokenPath;
  String host;
  String clientId;
  String codeVerifier = "";
  String fieldToken = "token";
  bool authenticating = false;
  bool ignoreStoredToken = false;
  late Uri redirectEndpoint;

  OauthClient(this.host,this.clientId,
      { localRedirect = "http://0.0.0.0:7777/",
        this.authPath = "oauth",
        this.tokenPath = "api/token" }) {
    redirectEndpoint = kIsWeb ? Uri.base : Uri.parse(localRedirect);
  }

  authenticate(callBack) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String token = prefs.getString(fieldToken) ?? "";
    if (!ignoreStoredToken && token.isNotEmpty) {
      callBack(oauth2.Client(oauth2.Credentials(token)));
      return;
    }
    _logMsg("Token not found, beginning oauth");
    authenticating = true;
    codeVerifier = _createCodeVerifier();
    prefs.setString("code_verifier", codeVerifier);

    oauth2.AuthorizationCodeGrant grant = oauth2.AuthorizationCodeGrant(
        clientId, Uri.parse("$host/$authPath"), Uri.parse("$host/$tokenPath"),
        httpClient: http.Client(), codeVerifier: codeVerifier);

    final authorizationUrl =
    grant.getAuthorizationUrl(redirectEndpoint, scopes: []);
    await _openAuthorizationServerLogin(authorizationUrl);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) _runRedirectServer("0.0.0.0",7777,callBack);
  }

  void decode(String code,callBack) async { //logMsg("Decoding: $code");
    _getClient(kIsWeb ? await _consumeVerifier() : codeVerifier, code).then((client) async {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (client != null) {
        _logMsg("Storing token");
        prefs.setString(fieldToken, client.credentials.accessToken);
      }
      callBack(client);
    });
    authenticating = false;
    if (!kIsWeb) closeInAppWebView();
  }

  void deleteToken(token) {
    final headers = { "Authorization": "Bearer $token", };
    Uri uri = Uri.parse('https://$host/$tokenPath');
    http.delete(uri,headers: headers).then((value) {
      _logMsg("Deleted Token Response: ${value.body}");
    });
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove("token");
    }).onError((error, stackTrace) {
      _logMsg("Shared Preference Error: $error");
    });
  }

  void _errMsg(String msg, callBack) {
    authenticating = false;
    _logMsg(msg); callBack("");
  }

  void _logMsg(String msg) { print(msg); }

  Future<void> _openAuthorizationServerLogin(Uri authUri) async {
    var authUriString = 'https://${authUri.toString()}';
    if (kIsWeb) {
      await launchUrl(Uri.parse(authUriString), mode :  LaunchMode.inAppBrowserView, webOnlyWindowName: "_self");
    }
    else {
      _logMsg("Launching WebView");
      webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
      webViewController.loadRequest(Uri.parse(authUriString));
    }
  }

  void _runRedirectServer(String address, int port, callBack) async {
    var server =  await HttpServer.bind(address,port); //TODO: use 'then' for error checking
    await server.forEach((HttpRequest request) {
      decode(request.uri.queryParameters['code'] ?? "", callBack);
      request.response.close();
      server.close();
    });
  }

  Future<oauth2.Client?> _getClient(String verifier, String? code) async {
    final grant = oauth2.AuthorizationCodeGrant(
        clientId,
        Uri.https(host, "/$authPath"),
        Uri.https(host, "/$tokenPath"),
        httpClient: http.Client(),
        codeVerifier: verifier);
    String ep = redirectEndpoint.toString().split("?").first;
    grant.getAuthorizationUrl(Uri.parse(ep), scopes: []);
    return grant.handleAuthorizationCode(code ?? "");
  }

  Future<String> _consumeVerifier() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String verifier = prefs.getString("code_verifier") ?? "";
    prefs.remove("code_verifier");
    return verifier;
  }

  static String _createCodeVerifier() {
    return List.generate(
        128, (i) => _charset[Random.secure().nextInt(_charset.length)]).join();
  }

}