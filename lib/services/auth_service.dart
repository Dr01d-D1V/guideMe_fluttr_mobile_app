import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'api_client.dart';

class AuthService {
  static String get baseUrl => AppConfig.baseUrl;

  // Lazily instantiated so Google Play Services IPC is deferred until
  // the user actually taps "Continue with Google".
  // TODO: Replace with your actual Google Web Client ID
  static GoogleSignIn? _googleSignInInstance;
  static GoogleSignIn get _googleSignIn => _googleSignInInstance ??= GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: dotenv.env['GOOGLE_ANDROID_CLIENT_ID'] ?? 'YOUR_ANDROID_CLIENT_ID.apps.googleusercontent.com',
        // serverClientId: dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com',
      );

  // ─── Session helpers ────────────────────────────────────────
  Future<void> _saveSession(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('user', jsonEncode(user));
  }

  static Future<String?> getAccessToken() => ApiClient.getAccessToken();

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('user');
    if (userJson != null) return jsonDecode(userJson);
    return null;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isLoggedIn');
    await prefs.remove('user');
    await ApiClient.clearSession();
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  static Future<bool> hasSeenIntro() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hasSeenIntro') ?? false;
  }

  static Future<void> setIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenIntro', true);
  }

  // ─── Email/Password Signup ───────────────────────────────────
  Future<AuthResponse> signup({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final formFields = [
        {'id': 'email', 'value': email},
        {'id': 'password', 'value': password},
        {'id': 'name', 'value': name},
      ];

      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'formFields': formFields}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'OK') {
        await _saveSession(data['user'] ?? {});
        await ApiClient.saveSession(response);
        // Onboarding is embedded in the signup response. Fall back to
        // /auth/me only if the backend omits it.
        final onboarding = data['onboarding'] as Map<String, dynamic>?
            ?? (await ApiClient.fetchMe())?['onboarding'] as Map<String, dynamic>?;
        return AuthResponse(
          success: true,
          user: data['user'],
          onboarding: onboarding,
        );
      } else if (data['status'] == 'FIELD_ERROR') {
        final errors = <String, String>{};
        for (var field in data['formFields']) {
          errors[field['id']] = field['error'];
        }
        return AuthResponse(success: false, fieldErrors: errors);
      } else {
        return AuthResponse(
          success: false,
          generalError: data['message'] ?? 'Signup failed',
        );
      }
    } catch (e) {
      return AuthResponse(success: false, generalError: 'Network error: $e');
    }
  }

  // ─── Email/Password Sign In ─────────────────────────────────
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final formFields = [
        {'id': 'email', 'value': email},
        {'id': 'password', 'value': password},
      ];

      final response = await http.post(
        Uri.parse('$baseUrl/auth/signin'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'formFields': formFields}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'OK') {
        await _saveSession(data['user'] ?? {});
        await ApiClient.saveSession(response);
        // Onboarding is embedded in the signin response. Fall back to
        // /auth/me only if the backend omits it.
        final onboarding = data['onboarding'] as Map<String, dynamic>?
            ?? (await ApiClient.fetchMe())?['onboarding'] as Map<String, dynamic>?;
        return AuthResponse(
          success: true,
          user: data['user'],
          onboarding: onboarding,
        );
      } else if (data['status'] == 'FIELD_ERROR') {
        final errors = <String, String>{};
        for (var field in data['formFields']) {
          errors[field['id']] = field['error'];
        }
        return AuthResponse(success: false, fieldErrors: errors);
      } else if (data['status'] == 'WRONG_CREDENTIALS_ERROR') {
        return AuthResponse(
          success: false,
          generalError: 'Incorrect email or password',
        );
      } else {
        return AuthResponse(
          success: false,
          generalError: data['message'] ?? 'Sign in failed',
        );
      }
    } catch (e) {
      return AuthResponse(success: false, generalError: 'Network error: $e');
    }
  }

  // ─── Google Sign In ─────────────────────────────────────────
  Future<AuthResponse> signInWithGoogle() async {
    try {
      // Sign out first so the account picker always appears.
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the picker.
        return AuthResponse(success: false, generalError: 'Google sign-in cancelled');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final idToken = googleAuth.idToken;
      if (idToken == null) {
        // idToken is only populated when serverClientId (web client ID) is set.
        await _googleSignIn.signOut();
        return AuthResponse(
          success: false,
          generalError:
              'Google sign-in failed: could not retrieve ID token. '
              'Ensure the Web Client ID is set in AuthService.',
        );
      }

      final response = await http.post(
        Uri.parse('$baseUrl/auth/signinup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'thirdPartyId': 'google',
          'idToken': idToken,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'OK') {
        await _saveSession(data['user'] ?? {});
        await ApiClient.saveSession(response);
        final onboarding = data['onboarding'] as Map<String, dynamic>?
            ?? (await ApiClient.fetchMe())?['onboarding'] as Map<String, dynamic>?;
        return AuthResponse(
          success: true,
          user: data['user'],
          isNewUser: data['createdNewUser'] ?? false,
          onboarding: onboarding,
        );
      } else {
        await _googleSignIn.signOut();
        return AuthResponse(
          success: false,
          generalError: data['message'] ?? 'Google sign-in failed',
        );
      }
    } catch (e) {
      await _googleSignIn.signOut();
      return AuthResponse(success: false, generalError: 'Google sign-in error: $e');
    }
  }

  // ─── Passwordless OTP: Send Code ────────────────────────────
  Future<OtpResponse> sendOtp({required String email}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/passwordless/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'OK') {
        return OtpResponse(
          success: true,
          deviceId: data['deviceId'],
          preAuthSessionId: data['preAuthSessionId'],
        );
      } else {
        return OtpResponse(
          success: false,
          error: data['message'] ?? 'Failed to send OTP',
        );
      }
    } catch (e) {
      return OtpResponse(success: false, error: 'Network error: $e');
    }
  }

  // ─── Passwordless OTP: Verify Code ──────────────────────────
  // Onboarding state is embedded in the response — no /auth/me call needed.
  Future<AuthResponse> verifyOtp({
    required String preAuthSessionId,
    required String code,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/passwordless/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pre_auth_session_id': preAuthSessionId,
          'user_input_code': code,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['status'] == 'OK') {
        await _saveSession(data['user'] ?? {});
        await ApiClient.saveSession(response);
        return AuthResponse(
          success: true,
          user: data['user'],
          isNewUser: data['createdNewUser'] ?? false,
          onboarding: data['onboarding'] as Map<String, dynamic>?,
        );
      } else if (data['status'] == 'INCORRECT_USER_INPUT_CODE_ERROR') {
        return AuthResponse(
          success: false,
          generalError:
              'Incorrect OTP. ${data['maximumCodeInputAttempts'] - data['failedCodeInputAttemptCount']} attempts remaining.',
        );
      } else if (data['status'] == 'EXPIRED_USER_INPUT_CODE_ERROR') {
        return AuthResponse(
          success: false,
          generalError: 'OTP has expired. Please request a new one.',
        );
      } else {
        return AuthResponse(
          success: false,
          generalError: data['message'] ?? 'Verification failed',
        );
      }
    } catch (e) {
      return AuthResponse(success: false, generalError: 'Network error: $e');
    }
  }

  // ─── Resend OTP ─────────────────────────────────────────────
  // Re-starts a new passwordless session for the same email.
  Future<OtpResponse> resendOtp({required String email}) async {
    return sendOtp(email: email);
  }

  // ─── Email Code Verification ─────────────────────────────────

  /// The user copies the code from their email and submits it here.
  /// Hits POST /auth/verify-email-token?token=<code>
  static Future<AuthResponse> resendVerificationEmail({
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/resend-verification-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return AuthResponse(success: true);
      } else {
        return AuthResponse(
          success: false,
          generalError: data['message'] ?? 'Failed to resend verification email.',
        );
      }
    } catch (e) {
      return AuthResponse(success: false, generalError: 'Network error: $e');
    }
  }

  static Future<AuthResponse> verifyEmailToken({
    required String token,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/auth/verify-email-token')
          .replace(queryParameters: {'token': token});

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await ApiClient.saveSession(response);
        return AuthResponse(success: true);
      } else {
        return AuthResponse(
          success: false,
          generalError: data['message'] ?? 'Invalid or expired code.',
        );
      }
    } catch (e) {
      return AuthResponse(
        success: false,
        generalError: 'Network error: $e',
      );
    }
  }
}

// ─── Response Models ────────────────────────────────────────────

class AuthResponse {
  final bool success;
  final Map<String, dynamic>? user;
  final Map<String, String>? fieldErrors;
  final String? generalError;
  final bool isNewUser;
  final Map<String, dynamic>? onboarding;

  /// The `resume_step` value from the onboarding payload, or null.
  String? get resumeStep => onboarding?['resume_step'] as String?;

  /// True when the backend reports onboarding is fully complete.
  bool get onboardingComplete => onboarding?['onboarding_complete'] == true;

  /// Like [resumeStep], but corrects for the case where the backend returns
  /// `resume_step: "email_verification"` while the step data already shows
  /// `email_verified: true`. In that case, walk the steps list to find the
  /// first entry where `completed != true` and return that step name instead.
  String? get effectiveResumeStep {
    final step = resumeStep;
    if (step != 'email_verification') return step;

    final steps = onboarding?['steps'] as List?;
    if (steps == null) return step;

    // Check whether email is actually verified in the step data.
    bool emailActuallyVerified = false;
    for (final s in steps) {
      final m = s as Map<String, dynamic>;
      if (m['step'] == 'email_verification') {
        final d = m['data'] as Map<String, dynamic>?;
        emailActuallyVerified = d?['email_verified'] == true;
        break;
      }
    }

    if (!emailActuallyVerified) return step; // email really not verified yet

    // Email is verified — find the first genuinely incomplete step.
    for (final s in steps) {
      final m = s as Map<String, dynamic>;
      if (m['step'] != 'email_verification' && m['completed'] != true) {
        return m['step'] as String?;
      }
    }
    return null; // all steps done → home
  }

  AuthResponse({
    required this.success,
    this.user,
    this.fieldErrors,
    this.generalError,
    this.isNewUser = false,
    this.onboarding,
  });
}

class OtpResponse {
  final bool success;
  final String? deviceId;
  final String? preAuthSessionId;
  final String? flowType;
  final String? error;

  OtpResponse({
    required this.success,
    this.deviceId,
    this.preAuthSessionId,
    this.flowType,
    this.error,
  });
}
