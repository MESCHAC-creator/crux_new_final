import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/error_handler_service.dart';
import '../providers/locale_provider.dart';
import '../l10n/app_translations.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();
  final _errorHandler = ErrorHandlerService();

  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // Inline error states
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  late AnimationController _bgController;
  late AnimationController _contentController;
  late AnimationController _pulseController;
  late AnimationController _buttonController;
  late AnimationController _particleController;

  late Animation<double> _headerFade;
  late Animation<double> _headerScale;
  late Animation<Offset> _nameSlide;
  late Animation<double> _nameFade;
  late Animation<Offset> _emailSlide;
  late Animation<double> _emailFade;
  late Animation<Offset> _passSlide;
  late Animation<double> _passFade;
  late Animation<Offset> _confirmSlide;
  late Animation<double> _confirmFade;
  late Animation<Offset> _buttonSlide;
  late Animation<double> _buttonFade;
  late Animation<Offset> _footerSlide;
  late Animation<double> _footerFade;

  late Animation<double> _pulseAnim;
  late Animation<double> _buttonScale;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
    );
    _headerScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.0, 0.35, curve: Curves.easeOutBack)),
    );

    _nameSlide = Tween<Offset>(begin: const Offset(-0.6, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.2, 0.45, curve: Curves.easeOutCubic)),
    );
    _nameFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.2, 0.45, curve: Curves.easeOut)),
    );

    _emailSlide = Tween<Offset>(begin: const Offset(0.6, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.3, 0.55, curve: Curves.easeOutCubic)),
    );
    _emailFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.3, 0.55, curve: Curves.easeOut)),
    );

    _passSlide = Tween<Offset>(begin: const Offset(-0.6, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.4, 0.65, curve: Curves.easeOutCubic)),
    );
    _passFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.4, 0.65, curve: Curves.easeOut)),
    );

    _confirmSlide = Tween<Offset>(begin: const Offset(0.6, 0), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.5, 0.75, curve: Curves.easeOutCubic)),
    );
    _confirmFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.5, 0.75, curve: Curves.easeOut)),
    );

    _buttonSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.6, 0.85, curve: Curves.easeOutBack)),
    );
    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.6, 0.85, curve: Curves.easeOut)),
    );

    _footerSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.75, 1.0, curve: Curves.easeOut)),
    );
    _footerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.75, 1.0, curve: Curves.easeOut)),
    );

    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _buttonScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeIn),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _contentController.forward();
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _contentController.dispose();
    _pulseController.dispose();
    _buttonController.dispose();
    _particleController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    // Clear previous errors
    setState(() {
      _nameError = null;
      _emailError = null;
      _passwordError = null;
      _confirmError = null;
    });

    // Inline validation
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    bool hasError = false;

    if (name.isEmpty) {
      setState(() => _nameError = 'Entrez votre nom complet');
      hasError = true;
    } else if (name.length < 2) {
      setState(() => _nameError = 'Le nom doit faire au moins 2 caractères');
      hasError = true;
    }

    if (email.isEmpty) {
      setState(() => _emailError = 'Entrez votre adresse email');
      hasError = true;
    } else if (!email.contains('@') || !email.contains('.')) {
      setState(() => _emailError = 'Format invalide (ex: nom@domaine.com)');
      hasError = true;
    }

    if (pass.isEmpty) {
      setState(() => _passwordError = 'Entrez un mot de passe');
      hasError = true;
    } else if (pass.length < 6) {
      setState(() => _passwordError = 'Minimum 6 caractères requis');
      hasError = true;
    }

    if (confirm.isEmpty) {
      setState(() => _confirmError = 'Confirmez votre mot de passe');
      hasError = true;
    } else if (pass != confirm) {
      setState(() => _confirmError = 'Les mots de passe ne correspondent pas');
      hasError = true;
    }

    if (hasError) return;

    await _buttonController.forward();
    await _buttonController.reverse();

    setState(() => _isLoading = true);
    try {
      final user = await _authService.signUp(
        email: email,
        password: pass,
        name: name,
      );
      if (mounted && user != null) {
        Navigator.of(context).pushReplacementNamed('/home', arguments: user);
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('email-already-in-use') || msg.contains('déjà utilisé')) {
        setState(() => _emailError = 'Cet email est déjà utilisé');
      } else if (msg.contains('invalid-email') || msg.contains('invalide')) {
        setState(() => _emailError = 'Format d\'email invalide');
      } else if (msg.contains('weak-password') || msg.contains('trop faible')) {
        setState(() => _passwordError = 'Mot de passe trop faible');
      } else if (msg.contains('network') || msg.contains('réseau')) {
        _errorHandler.showWarningSnackBar(context, 'Pas de connexion Internet');
      } else {
        _errorHandler.showError(context, msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (_, __) {
          final t = _bgController.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(
                  math.cos(t * 2 * math.pi) * 0.8,
                  math.sin(t * 2 * math.pi) * 0.8,
                ),
                end: Alignment(
                  math.cos(t * 2 * math.pi + math.pi) * 0.8,
                  math.sin(t * 2 * math.pi + math.pi) * 0.8,
                ),
                colors: const [
                  Color(0xFF1A0030),
                  Color(0xFF6B003B),
                  Color(0xFFCC0033),
                  Color(0xFF3D0070),
                ],
                stops: const [0.0, 0.35, 0.65, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Floating decorative particles
                for (int i = 0; i < 6; i++)
                  _FloatingParticle(index: i, controller: _particleController),

                // Main content
                SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: Column(
                      children: [
                        // Back button
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FadeTransition(
                            opacity: _headerFade,
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Header
                        FadeTransition(
                          opacity: _headerFade,
                          child: ScaleTransition(
                            scale: _headerScale,
                            child: _buildHeader(lang),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Form card
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Name field
                              SlideTransition(position: _nameSlide,
                                child: FadeTransition(opacity: _nameFade,
                                  child: _GlassTextField(
                                    controller: _nameController,
                                    label: AppTranslations.t('full_name', lang),
                                    hint: 'Jean Dupont',
                                    icon: Icons.person_outline,
                                    errorText: _nameError,
                                    onChanged: (_) => setState(() => _nameError = null),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Email field
                              SlideTransition(position: _emailSlide,
                                child: FadeTransition(opacity: _emailFade,
                                  child: _GlassTextField(
                                    controller: _emailController,
                                    label: AppTranslations.t('email', lang),
                                    hint: 'email@exemple.com',
                                    icon: Icons.email_outlined,
                                    keyboardType: TextInputType.emailAddress,
                                    errorText: _emailError,
                                    onChanged: (_) => setState(() => _emailError = null),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Password field
                              SlideTransition(position: _passSlide,
                                child: FadeTransition(opacity: _passFade,
                                  child: _GlassTextField(
                                    controller: _passwordController,
                                    label: AppTranslations.t('password', lang),
                                    hint: '••••••••',
                                    icon: Icons.lock_outline,
                                    obscureText: !_showPassword,
                                    errorText: _passwordError,
                                    onChanged: (_) => setState(() => _passwordError = null),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showPassword ? Icons.visibility_off : Icons.visibility,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() => _showPassword = !_showPassword),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Confirm password field
                              SlideTransition(position: _confirmSlide,
                                child: FadeTransition(opacity: _confirmFade,
                                  child: _GlassTextField(
                                    controller: _confirmPasswordController,
                                    label: AppTranslations.t('confirm_password', lang),
                                    hint: '••••••••',
                                    icon: Icons.lock_outline,
                                    obscureText: !_showConfirmPassword,
                                    errorText: _confirmError,
                                    onChanged: (_) => setState(() => _confirmError = null),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showConfirmPassword ? Icons.visibility_off : Icons.visibility,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                              // Sign up button
                              SlideTransition(
                                position: _buttonSlide,
                                child: FadeTransition(
                                  opacity: _buttonFade,
                                  child: ScaleTransition(
                                    scale: _buttonScale,
                                    child: _buildSignUpButton(lang),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Footer
                        SlideTransition(
                          position: _footerSlide,
                          child: FadeTransition(
                            opacity: _footerFade,
                            child: _buildFooter(lang),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(String lang) {
    return Column(
      children: [
        ScaleTransition(
          scale: _pulseAnim,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE53935), Color(0xFF6A1B9A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppTranslations.t('create_account', lang),
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Rejoignez CRUX dès maintenant',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.white70,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildSignUpButton(String lang) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFF6A1B9A)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE53935).withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _signUp,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                )
              : Text(
                  AppTranslations.t('signup', lang),
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFooter(String lang) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          AppTranslations.t('have_account', lang),
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Text(
            AppTranslations.t('login', lang),
            style: GoogleFonts.poppins(
              color: const Color(0xFFE53935),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: const Color(0xFFE53935),
            ),
          ),
        ),
      ],
    );
  }
}

// Floating animated particle for background
class _FloatingParticle extends StatelessWidget {
  final int index;
  final AnimationController controller;

  const _FloatingParticle({required this.index, required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final rng = math.Random(index * 31 + 7);
    final startX = rng.nextDouble() * size.width;
    final startY = rng.nextDouble() * size.height;
    final radius = 18.0 + rng.nextDouble() * 40;
    final speed = 0.15 + rng.nextDouble() * 0.25;
    final phase = rng.nextDouble();

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = (controller.value + phase) % 1.0;
        final dy = -size.height * 0.4 * t;
        final dx = math.sin(t * math.pi * 2 * speed) * 60;
        return Positioned(
          left: startX + dx,
          top: startY + dy,
          child: Opacity(
            opacity: (0.06 + rng.nextDouble() * 0.08) * (1 - t),
            child: Container(
              width: radius,
              height: radius,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  index.isEven ? const Color(0xFFE53935) : const Color(0xFF6A1B9A),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Reusable glass text field with inline error support
class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.poppins(
          color: hasError ? Colors.redAccent : Colors.white70,
          fontSize: 13,
        ),
        hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 14),
        prefixIcon: Icon(icon, color: hasError ? Colors.redAccent : Colors.white70, size: 20),
        suffixIcon: suffixIcon,
        errorText: errorText,
        errorStyle: GoogleFonts.poppins(
          color: Colors.redAccent,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: hasError
            ? Colors.red.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: hasError
              ? const BorderSide(color: Colors.redAccent, width: 1.5)
              : BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: hasError
              ? const BorderSide(color: Colors.redAccent, width: 2)
              : const BorderSide(color: Color(0xFFE53935), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}
