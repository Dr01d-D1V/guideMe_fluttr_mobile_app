import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/api_client.dart';
import '../models/route_entry.dart';

// const String _baseUrl = 'http://192.168.100.35:8000';
const String _baseUrl = 'http://192.168.18.8:8000';

class ApiService {
  final http.Client _client;
  ApiService(this._client);

  Future<Map<String, String>> _authHeaders() async {
    final token = await ApiClient.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> saveTravelPatterns(
      Map<String, dynamic> payload) async {
    final headers = await _authHeaders();
    final response = await _client.post(
      Uri.parse('$_baseUrl/onboarding/travel-pattern'),
      headers: headers,
      body: jsonEncode(payload),
    );
    return _handle(response);
  }

  Future<Map<String, dynamic>> saveRoutes(
      Map<String, dynamic> payload) async {
    final headers = await _authHeaders();
    final response = await _client.post(
      Uri.parse('$_baseUrl/onboarding/routes'),
      headers: headers,
      body: jsonEncode(payload),
    );
    return _handle(response);
  }

  Future<Map<String, dynamic>> saveAlertPreferences(
      Map<String, dynamic> payload) async {
    final headers = await _authHeaders();
    final response = await _client.post(
      Uri.parse('$_baseUrl/onboarding/alert-preferences'),
      headers: headers,
      body: jsonEncode(payload),
    );
    return _handle(response);
  }

  Future<List<RouteOption>> fetchRouteOptions(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    final headers = await _authHeaders();
    final response = await _client.get(
      Uri.parse(
        '$_baseUrl/maps/directions'
        '?origin=$originLat,$originLng'
        '&destination=$destLat,$destLng'
        '&alternatives=true',
      ),
      headers: headers,
    );
    final data = _handle(response);
    return (data['routes'] as List<dynamic>? ?? [])
        .map((r) => RouteOption.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Map<String, dynamic> _handle(http.Response response) {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw Exception(data['message'] ?? 'An error occurred (${response.statusCode})');
  }
}

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(http.Client()),
);
