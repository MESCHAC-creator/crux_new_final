import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../services/auth_service.dart';
import '../services/error_handler_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _errorHandler = ErrorHandlerService();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _showPassword = false;

  // Inline error states
  String? _emailError;
  String? _passwordError;

  // Animation controllers
  late AnimationController _bgController;
  late AnimationController _contentController;
  late AnimationController _pulseController;
  late AnimationController _buttonController;

  // Content animations (staggered)
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleFade;
  late Animation<Offset> _emailSlide;
  late Animation<double> _emailFade;
  late Animation<Offset> _passwordSlide;
  late Animation<double> _passwordFade;
  late Animation<Offset> _buttonSlide;
  late Animation<double> _buttonFade;
  late Animation<Offset> _footerSlide;
  late Animation<double> _footerFade;

  late Animation<double> _pulsAnim;
  late Animation<double> _buttonScale;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _contentController.forward();
    _pulseController.repeat(reverse: true);
  }

  void _setupAnimations() {
    // Background gradient rotation
    _bgController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();

    // Content stagger controller
    _contentController = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );

    // Pulse for logo
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    // Button press controller
    _buttonController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );

    // Logo
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.0, 0.4, curve: Curves.elasticOut)),
    );

    // Title
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.15, 0.45, curve: Curves.easeOutCubic)),
    );
    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.15, 0.45)),
    );

    // Email field
    _emailSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.3, 0.6, curve: Curves.easeOutCubic)),
    );
    _emailFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.3, 0.6)),
    );

    // Password field
    _passwordSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.45, 0.72, curve: Curves.easeOutCubic)),
    );
    _passwordFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.45, 0.72)),
    );

    // Button
    _buttonSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.6, 0.85, curve: Curves.easeOutCubic)),
    );
    _buttonFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.6, 0.85)),
    );

    // Footer
    _footerSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.75, 1.0, curve: Curves.easeOut)),
    );
    _footerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _contentController, curve: const Interval(0.75, 1.0)),
    );

    // Pulse
    _pulsAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Button press
    _buttonScale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _buttonController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    _contentController.dispose();
    _pulseController.dispose();
    _buttonController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Validate fields locally and set inline errors. Returns true if valid.
  bool _validateFields() {
    String? emailErr;
    String? passErr;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      emailErr = 'Entrez votre adresse email';
    } else if (!email.contains('@')) {
      emailErr = 'Format invalide (ex: nom@domaine.com)';
    }

    if (password.isEmpty) {
      passErr = 'Entrez votre mot de passe';
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
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      if (mounted) {
        _errorHandler.showErrorDialog(context, '❌ Connexion Google échouée',
            e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    if (!_validateFields()) return;

    await _buttonController.forward();
    await _buttonController.reverse();

    setState(() => _isLoading = true);
    try {
      await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');

      if (msg.contains('wrong-password') ||
          msg.contains('invalid-credential') ||
          msg.contains('INVALID_LOGIN_CREDENTIALS') ||
          msg.contains('incorrect')) {
        setState(() => _passwordError = 'Mot de passe incorrect');
      } else if (msg.contains('user-not-found') || msg.contains('no user') || msg.contains('non trouvé')) {
        setState(() => _emailError = 'Aucun compte trouvé avec cet email');
      } else if (msg.contains('invalid-email') || msg.contains('invalide')) {
        setState(() => _emailError = 'Format d\'email invalide (ex: nom@domaine.com)');
      } else if (msg.contains('too-many-requests') || msg.contains('Trop de tentatives')) {
        _errorHandler.showWarningSnackBar(
            context, 'Trop de tentatives. Réessayez dans quelques minutes.');
      } else if (msg.contains('network') || msg.contains('réseau')) {
        _errorHandler.showWarningSnackBar(
            context, 'Pas de connexion Internet. Vérifiez votre réseau.');
      } else if (msg.contains('disabled') || msg.contains('désactivé')) {
        _errorHandler.showErrorDialog(
            context, 'Compte désactivé', 'Compte désactivé. Contactez le support.');
      } else {
        _errorHandler.showErrorDialog(context, '❌ Connexion échouée', msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    String? dialogError;
    bool sending = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A0030),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'Mot de passe oublié',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Entrez votre adresse email pour recevoir un lien de réinitialisation.',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'email@exemple.com',
                      hintStyle: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.email_outlined, color: Colors.white60, size: 20),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      errorText: dialogError,
                      errorStyle: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    ),
                    onChanged: (_) => setDialogState(() => dialogError = null),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Annuler',
                      style: GoogleFonts.poppins(color: Colors.white54, fontWeight: FontWeight.w600)),
                ),
                TextButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = emailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            setDialogState(() => dialogError = 'Entrez un email valide');
                            return;
                          }
                          setDialogState(() => sending = true);
                          try {
                            await _authService.resetPassword(email);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              if (mounted) {
                                _errorHandler.showSuccessSnackBar(
                                  context,
                                  'Email de réinitialisation envoyé ! Vérifiez votre boîte mail.',
                                );
                              }
                            }
                          } catch (e) {
                            final msg = e.toString().replaceFirst('Exception: ', '');
                            String errorMsg;
                            if (msg.contains('user-not-found') || msg.contains('non trouvé')) {
                              errorMsg = 'Aucun compte avec cet email';
                            } else if (msg.contains('network') || msg.contains('réseau')) {
                              errorMsg = 'Problème réseau';
                            } else {
                              errorMsg = msg;
                            }
                            setDialogState(() {
                              dialogError = errorMsg;
                              sending = false;
                            });
                          }
                        },
                  child: sending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                        )
                      : Text('Envoyer',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFFB71C1C),
                            fontWeight: FontWeight.w700,
                          )),
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
    return Scaffold(
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _bgController,
            builder: (_, __) {
              final t = _bgController.value;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(math.cos(t * 2 * math.pi), math.sin(t * 2 * math.pi)),
                    end: Alignment(-math.cos(t * 2 * math.pi), -math.sin(t * 2 * math.pi)),
                    colors: const [
                      Color(0xFFB71C1C),
                      Color(0xFF6A1B9A),
                      Color(0xFF3498DB),
                      Color(0xFF6A1B9A),
                    ],
                    stops: [0.0, 0.4 + t * 0.2, 0.7 + t * 0.1, 1.0],
                  ),
                ),
              );
            },
          ),

          // Floating circles decoration
          ...List.generate(5, (i) => _FloatingCircle(index: i, controller: _bgController)),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const SizedBox(height: 56),

                  // Animated logo
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: ScaleTransition(
                        scale: _pulsAnim,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 30,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.videocam_rounded,
                              color: Color(0xFFB71C1C), size: 52),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleFade,
                      child: Column(
                        children: [
                          Text(
                            'CRUX',
                            style: GoogleFonts.poppins(
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                          Text(
                            'Connexion à votre compte',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              color: Colors.white70,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Glass card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        // Email
                        SlideTransition(
                          position: _emailSlide,
                          child: FadeTransition(
                            opacity: _emailFade,
                            child: _GlassTextField(
                              controller: _emailController,
                              hint: 'Email',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              errorText: _emailError,
                              onChanged: (_) => setState(() => _emailError = null),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Password
                        SlideTransition(
                          position: _passwordSlide,
                          child: FadeTransition(
                            opacity: _passwordFade,
                            child: _GlassTextField(
                              controller: _passwordController,
                              hint: 'Mot de passe',
                              icon: Icons.lock_outlined,
                              obscure: !_showPassword,
                              errorText: _passwordError,
                              onChanged: (_) => setState(() => _passwordError = null),
                              suffix: IconButton(
                                icon: Icon(
                                  _showPassword ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Forgot password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: Text(
                              'Mot de passe oublié ?',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Login button
                        SlideTransition(
                          position: _buttonSlide,
                          child: FadeTransition(
                            opacity: _buttonFade,
                            child: ScaleTransition(
                              scale: _buttonScale,
                              child: SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFFB71C1C),
                                    elevation: 8,
                                    shadowColor: Colors.black38,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16)),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 22, height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor: AlwaysStoppedAnimation(Color(0xFFB71C1C)),
                                          ),
                                        )
                                      : Text(
                                          'Se connecter',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Divider
                        Row(children: [
                          Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('ou', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
                          ),
                          Expanded(child: Divider(color: Colors.white24, thickness: 1)),
                        ]),
                        const SizedBox(height: 16),

                        // Google button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: OutlinedButton(
                            onPressed: (_isLoading || _isGoogleLoading) ? null : _handleGoogleLogin,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withOpacity(0.4), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              backgroundColor: Colors.white.withOpacity(0.08),
                            ),
                            child: _isGoogleLoading
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Google "G" logo
                                      Container(
                                        width: 24, height: 24,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Center(
                                          child: Text('G',
                                            style: TextStyle(
                                              color: Color(0xFF4285F4),
                                              fontWeight: FontWeight.w900,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Continuer avec Google',
                                        style: GoogleFonts.poppins(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Footer — Sign up link
                  SlideTransition(
                    position: _footerSlide,
                    child: FadeTransition(
                      opacity: _footerFade,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Pas encore de compte ? ',
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (_, a, __) => const SignUpScreen(),
                                transitionsBuilder: (_, anim, __, child) {
                                  return SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                                    child: child,
                                  );
                                },
                              ),
                            ),
                            child: Text(
                              'Créer un compte',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Floating decorative circles in the background
class _FloatingCircle extends StatelessWidget {
  final int index;
  final AnimationController controller;

  const _FloatingCircle({required this.index, required this.controller});

  @override
  Widget build(BuildContext context) {
    final sizes = [120.0, 80.0, 160.0, 60.0, 100.0];
    final positions = [
      const Offset(-40, 80),
      const Offset(300, 40),
      const Offset(250, 500),
      const Offset(-20, 450),
      const Offset(160, 650),
    ];
    final speeds = [0.3, 0.5, 0.2, 0.4, 0.35];

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = controller.value;
        final dy = math.sin((t + index * 0.2) * 2 * math.pi) * 20;
        return Positioned(
          left: positions[index].dx,
          top: positions[index].dy + dy * speeds[index] * 10,
          child: Container(
            width: sizes[index],
            height: sizes[index],
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
            ),
          ),
        );
      },
    );
  }
}

// Glass-morphism text field with inline error support
class _GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _GlassTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
        prefixIcon: Icon(icon, color: hasError ? Colors.redAccent : Colors.white60, size: 20),
        suffixIcon: suffix,
        errorText: errorText,
        errorStyle: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.w500),
        filled: true,
        fillColor: hasError
            ? Colors.red.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: hasError
              ? const BorderSide(color: Colors.redAccent, width: 1.5)
              : BorderSide(color: Colors.white.withOpacity(0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: hasError
              ? const BorderSide(color: Colors.redAccent, width: 2)
              : const BorderSide(color: Colors.white, width: 2),
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
