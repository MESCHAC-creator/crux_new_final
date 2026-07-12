import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/error_handler_service.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';
import '../models/user_model.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _errorHandler = ErrorHandlerService();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _showPassword = false;
  bool _rememberEmail = false;

  static const _emailPrefKey = 'crux_remembered_email';
  static const _rememberPrefKey = 'crux_remember_email';

  String? _emailError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberPrefKey) ?? false;
    if (remember) {
      final email = prefs.getString(_emailPrefKey) ?? '';
      if (mounted) {
        setState(() {
          _rememberEmail = true;
          _emailController.text = email;
        });
      }
    }
  }

  Future<void> _saveRememberedEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberEmail) {
      await prefs.setBool(_rememberPrefKey, true);
      await prefs.setString(_emailPrefKey, email);
    } else {
      await prefs.remove(_rememberPrefKey);
      await prefs.remove(_emailPrefKey);
    }
  }

  void _goHome() {
    final fb = FirebaseAuth.instance.currentUser;
    final user = fb == null
        ? null
        : UserModel(
            uid: fb.uid,
            email: fb.email ?? '',
            name: fb.displayName ?? fb.email?.split('@')[0] ?? 'Utilisateur',
          );
    Navigator.of(context).pushReplacementNamed('/home', arguments: user);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validateFields() {
    context.read<LocaleProvider>().locale.languageCode;
    String? emailErr;
    String? passErr;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      emailErr = AppTranslations.t('val_email_required', lang);
    } else if (!email.contains('@')) {
      emailErr = AppTranslations.t('val_email_invalid', lang);
    }

    if (password.isEmpty) {
      passErr = AppTranslations.t('val_pwd_required', lang);
    }

    setState(() {
      _emailError = emailErr;
      _passwordError = passErr;
    });

    return emailErr == null && passErr == null;
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (user != null && mounted) {
        _goHome();
      }
    } catch (e) {
      if (mounted) {
        final lang = context.read<LocaleProvider>().locale.languageCode;
        _errorHandler.showErrorDialog(
          context,
          '❌ ${AppTranslations.t('google_failed', lang)}',
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    if (!_validateFields()) return;

    setState(() => _isLoading = true);
    final email = _emailController.text.trim();
    try {
      await _authService.signIn(
        email: email,
        password: _passwordController.text,
      );
      await _saveRememberedEmail(email);
      if (mounted) _goHome();
    } catch (e) {
      if (!mounted) return;
      final lang = context.read<LocaleProvider>().locale.languageCode;
      final msg = e.toString().replaceFirst('Exception: ', '');

      if (msg.contains('wrong-password') ||
          msg.contains('invalid-credential') ||
          msg.contains('INVALID_LOGIN_CREDENTIALS') ||
          msg.contains('incorrect')) {
        setState(() => _passwordError = AppTranslations.t('auth_wrong_pwd', lang));
      } else if (msg.contains('user-not-found') || msg.contains('no user') || msg.contains('non trouvé')) {
        setState(() => _emailError = AppTranslations.t('auth_no_account', lang));
      } else if (msg.contains('invalid-email') || msg.contains('invalide')) {
        setState(() => _emailError = AppTranslations.t('auth_invalid_email_fmt', lang));
      } else {
        _errorHandler.showErrorDialog(
          context,
          '❌ ${AppTranslations.t('error', lang)}',
          _errorHandler.cleanErrorMessageL(msg, lang),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog(String lang) async {
    final emailController = TextEditingController();
    String? dialogError;
    bool sending = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF14141F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                AppTranslations.t('forgot_password', lang),
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppTranslations.t('reset_prompt', lang),
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: AppTranslations.t('reset_email_hint', lang),
                      hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.email_outlined, color: Colors.white60, size: 20),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      errorText: dialogError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                      ),
                    ),
                    onChanged: (_) => setDialogState(() => dialogError = null),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppTranslations.t('cancel', lang), style: GoogleFonts.poppins(color: Colors.white38)),
                ),
                TextButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            setDialogState(() => dialogError = AppTranslations.t('reset_valid_email', lang));
                            return;
                          }
                          setDialogState(() => sending = true);
                          try {
                            await _authService.resetPassword(email);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              if (mounted) {
                                _errorHandler.showSuccessSnackBar(context, AppTranslations.t('reset_sent', lang));
                              }
                            }
                          } catch (e) {
                            setDialogState(() {
                              dialogError = e.toString().replaceFirst('Exception: ', '');
                              sending = false;
                            });
                          }
                        },
                  child: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                      : Text(AppTranslations.t('reset_send', lang), style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E1A), Color(0xFF121624), Color(0xFF020205)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF7C5CFF)],
                    ).createShader(bounds),
                    child: Text(
                      'CRUX',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppTranslations.t('connecting', lang).toUpperCase(),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: const Color(0xFF8A8FA3),
                      letterSpacing: 2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _buildTextField(
                    controller: _emailController,
                    hint: AppTranslations.t('email', lang),
                    icon: Icons.email_outlined,
                    errorText: _emailError,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    hint: AppTranslations.t('password', lang),
                    icon: Icons.lock_outline,
                    obscure: !_showPassword,
                    errorText: _passwordError,
                    suffix: IconButton(
                      icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off, color: Colors.white38, size: 20),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _showForgotPasswordDialog(lang),
                        child: Text(
                          AppTranslations.t('forgot_password', lang),
                          style: GoogleFonts.spaceGrotesk(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildPrimaryButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    label: AppTranslations.t('login', lang),
                    loading: _isLoading,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white10)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          AppTranslations.t('or_divider', lang).toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(color: Colors.white10, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Expanded(child: Divider(color: Colors.white10)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSocialButton(
                    onPressed: _isGoogleLoading ? null : _handleGoogleLogin,
                    label: AppTranslations.t('sign_in_google', lang),
                    icon: Icons.g_mobiledata,
                    loading: _isGoogleLoading,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        AppTranslations.t('no_account', lang),
                        style: GoogleFonts.poppins(color: Colors.white38, fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
                        child: Text(
                          AppTranslations.t('create_account', lang),
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildLanguageSelector(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: errorText != null ? Colors.redAccent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 15),
              prefixIcon: Icon(icon, color: Colors.white38, size: 20),
              suffixIcon: suffix,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Text(errorText, style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildPrimaryButton({required VoidCallback? onPressed, required String label, bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: loading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
            : Text(label.toUpperCase(), style: GoogleFonts.poppins(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ),
    );
  }

  Widget _buildSocialButton({required VoidCallback? onPressed, required String label, required IconData icon, bool loading = false}) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Text(label, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
                ],
              ),
      ),
    );
  }

  Widget _buildSmallSocialButton({required VoidCallback onPressed, required IconData icon, required Color color}) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return Consumer<LocaleProvider>(
      builder: (context, lp, _) => DropdownButton<String>(
        value: lp.languageLabel,
        dropdownColor: const Color(0xFF14141F),
        underline: const SizedBox(),
        icon: const Icon(Icons.language, color: Colors.white38, size: 16),
        items: LocaleProvider.languages.keys.map((String lang) {
          return DropdownMenuItem<String>(
            value: lang,
            child: Text(lang, style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12)),
          );
        }).toList(),
        onChanged: (String? val) {
          if (val != null) lp.setLanguage(val);
        },
      ),
    );
  }
}
