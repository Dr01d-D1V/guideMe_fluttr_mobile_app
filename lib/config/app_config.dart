import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central configuration loaded from the `.env` file at startup.
///
/// Change [API_BASE_URL] in `.env` to update the backend host everywhere.
class AppConfig {
  AppConfig._();

  /// The backend base URL, e.g. `http://192.168.100.35:8000`.
  /// Defaults to localhost if the key is missing in .env.
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';
}
