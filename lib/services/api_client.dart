import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Authenticated HTTP client backed by secure storage.
///
/// SuperTokens returns the access token in the `st-access-token` response
/// header. Call [saveSession] after every successful auth response to persist
/// that token, then use [get] / [post] for all protected endpoints.
/// On a 401 "try refresh token" response the client automatically calls
/// POST /auth/session/refresh and retries the request once.
class ApiClient {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static String get baseUrl => AppConfig.baseUrl;

  // ─── Token lifecycle ─────────────────────────────────────────

  static Future<void> saveSession(http.Response response) async {
    final token = response.headers['st-access-token'];
    if (token != null && token.isNotEmpty) {
      await _storage.write(key: 'access_token', value: token);
    }
  }

  static Future<String?> getAccessToken() =>
      _storage.read(key: 'access_token');

  static Future<void> clearSession() => _storage.delete(key: 'access_token');

  // ─── Session refresh ─────────────────────────────────────────

  static Future<bool> _refreshSession() async {
    try {
      final token = await _storage.read(key: 'access_token');
      final response = await http
          .post(
            Uri.parse('$baseUrl/auth/session/refresh'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        await saveSession(response);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Runs [request], and on a 401 containing "try refresh token" refreshes
  /// the session and retries once.
  static Future<http.Response> _withRefresh(
      Future<http.Response> Function() request) async {
    final response = await request();
    if (response.statusCode == 401 &&
        response.body.toLowerCase().contains('try refresh token')) {
      if (await _refreshSession()) return request();
    }
    return response;
  }

  // ─── HTTP helpers ────────────────────────────────────────────

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _storage.read(key: 'access_token');
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String path) async {
    return _withRefresh(() async => http
        .get(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(json: false),
        )
        .timeout(const Duration(seconds: 15)));
  }

  static Future<http.Response> post(
      String path, Map<String, dynamic> body) async {
    return _withRefresh(() async => http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15)));
  }

  // ─── /auth/me ────────────────────────────────────────────────

  /// Fetches the current user's profile and onboarding state.
  /// Returns null on any failure.
  static Future<Map<String, dynamic>?> fetchMe() async {
    try {
      final response = await get('/auth/me');
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }
}
