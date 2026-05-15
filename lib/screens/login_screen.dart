import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../router/route_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();

  // 0 = email/password, 1 = passwordless OTP
  int _activeTab = 0;

  // Form keys
  final _emailPassFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _contactController = TextEditingController();

  // Errors
  String? _emailError;
  String? _passwordError;
  String? _contactError;
  String? _generalError;

  // State
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _clearErrors() {
    setState(() {
      _emailError = null;
      _passwordError = null;
      _contactError = null;
      _generalError = null;
    });
  }

  // ─── Validators ──────────────────────────────────────────────

  String? _validateEmail(String? value) {
    if (_emailError != null) return _emailError;
    if (value == null || value.isEmpty) return 'Email is required';
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) {
    if (_passwordError != null) return _passwordError;
    if (value == null || value.isEmpty) return 'Password is required';
    return null;
  }

  String? _validateContact(String? value) {
    if (_contactError != null) return _contactError;
    if (value == null || value.isEmpty) {
      return 'Enter your phone number or email';
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    final phoneRegex = RegExp(r'^\+?[\d\s\-\(\)]{7,}$');
    if (!emailRegex.hasMatch(value) && !phoneRegex.hasMatch(value)) {
      return 'Enter a valid email or phone number';
    }
    return null;
  }

  // ─── Navigation helper ───────────────────────────────────────

  void _navigateFromOnboarding(AuthResponse response, {String? email}) {
    if (response.effectiveResumeStep == 'email_verification') {
      context.go(
        Routes.emailVerification,
        extra: {
          'email': email ?? response.user?['email'] as String? ?? '',
          'user': response.user,
        },
      );
    } else {
      context.go(Routes.fromResumeStep(response.effectiveResumeStep));
    }
  }

  // ─── Email/Password Sign In ─────────────────────────────────

  Future<void> _handleEmailPassSignIn() async {
    _clearErrors();
    if (!_emailPassFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (response.success) {
        _navigateFromOnboarding(
          response,
          email: _emailController.text.trim(),
        );
      } else if (response.fieldErrors != null) {
        setState(() {
          _emailError = response.fieldErrors!['email'];
          _passwordError = response.fieldErrors!['password'];
        });
        _emailPassFormKey.currentState!.validate();
      } else {
        setState(() => _generalError = response.generalError);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── OTP Send ───────────────────────────────────────────────

  Future<void> _handleSendOtp() async {
    _clearErrors();
    if (!_otpFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _contactController.text.trim();
    final response = await _authService.sendOtp(email: email);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (response.success) {
      context.push(
        Routes.otpVerification,
        extra: {
          'contact': email,
          'deviceId': response.deviceId!,
          'preAuthSessionId': response.preAuthSessionId!,
        },
      );
    } else {
      setState(() => _generalError = response.error);
    }
  }

  // ─── Google Sign In ─────────────────────────────────────────

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isGoogleLoading = true;
      _generalError = null;
    });

    final response = await _authService.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isGoogleLoading = false);

    if (response.success) {
      _navigateFromOnboarding(response);
    } else {
      setState(() => _generalError = response.generalError);
    }
  }

  // ─── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              const Text(
                'Sign In',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text(
                    "Don't have an account? ",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  GestureDetector(
                    onTap: () {
                      context.go(Routes.signup);
                    },
                    child: Text(
                      'Sign Up',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Google button
              _googleButton(),
              const SizedBox(height: 24),

              // Divider
              _orDivider(),
              const SizedBox(height: 24),

              // Tab selector
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _tabButton('Email & Password', 0),
                    const SizedBox(width: 4),
                    _tabButton('Passwordless', 1),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // General error
              if (_generalError != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _generalError!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Active form
              if (_activeTab == 0) _buildEmailPassForm(),
              if (_activeTab == 1) _buildOtpForm(),

              const SizedBox(height: 24),

              // Terms
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  children: const [
                    TextSpan(text: 'By continuing, you agree to our '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Email/Password form ────────────────────────────────────

  Widget _buildEmailPassForm() {
    return Form(
      key: _emailPassFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Email *',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _emailController,
            decoration: InputDecoration(
              hintText: 'Email address',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: _validateEmail,
            onChanged: (_) => _clearErrors(),
          ),
          const SizedBox(height: 16),

          const Text('Password *',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              hintText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            validator: _validatePassword,
            onChanged: (_) => _clearErrors(),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _isLoading ? null : _handleEmailPassSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Sign In', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // ─── Passwordless OTP form ──────────────────────────────────

  Widget _buildOtpForm() {
    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "What's your phone number or email?",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contactController,
            decoration: InputDecoration(
              hintText: 'Enter phone number or email',
              prefixIcon: const Icon(Icons.person_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            validator: _validateContact,
            onChanged: (_) => _clearErrors(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Send OTP', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  // ─── Shared widgets ─────────────────────────────────────────

  Widget _tabButton(String label, int index) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _clearErrors();
          setState(() => _activeTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(13),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? Colors.black : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Widget _googleButton() {
    return OutlinedButton(
      onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: _isGoogleLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.g_mobiledata, color: Colors.red, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Continue with Google',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward, color: Colors.grey[400], size: 18),
                const SizedBox(width: 8),
              ],
            ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.grey[300])),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('or',
              style: TextStyle(color: Colors.grey[500], fontSize: 14)),
        ),
        Expanded(child: Divider(color: Colors.grey[300])),
      ],
    );
  }
}
