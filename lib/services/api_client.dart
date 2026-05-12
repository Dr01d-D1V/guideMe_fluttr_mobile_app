import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Authenticated HTTP client backed by secure storage.
///
/// SuperTokens returns the access token in the `st-access-token` response
/// header — not in the JSON body. Call [saveSession] after every successful
/// auth response to persist that token, then use [get] / [post] for all
/// protected endpoints.
class ApiClient {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const baseUrl = 'http://192.168.100.35:8000';

  // ─── Token lifecycle ─────────────────────────────────────────

  /// Reads `st-access-token` from response headers and stores it securely.
  /// Call this immediately after any successful auth endpoint response.
  static Future<void> saveSession(http.Response response) async {
    final token = response.headers['st-access-token'];
    if (token != null && token.isNotEmpty) {
      await _storage.write(key: 'access_token', value: token);
    }
  }

  /// Returns the stored access token, or null if not authenticated.
  static Future<String?> getAccessToken() =>
      _storage.read(key: 'access_token');

  /// Deletes the stored access token. Call on logout.
  static Future<void> clearSession() => _storage.delete(key: 'access_token');

  // ─── HTTP helpers ────────────────────────────────────────────

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final token = await _storage.read(key: 'access_token');
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String path) async {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(json: false),
    );
  }

  static Future<http.Response> post(
      String path, Map<String, dynamic> body) async {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }
}
