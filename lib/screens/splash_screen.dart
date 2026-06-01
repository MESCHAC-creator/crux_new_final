import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _bgController;
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _particleController;
  late AnimationController _rippleController;

  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _logoRotate;
  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  late Animation<double> _subtitleFade;
  late Animation<Offset> _subtitleSlide;
  late Animation<double> _loaderFade;
  late Animation<double> _ripple1;
  late Animation<double> _ripple2;
  late Animation<double> _ripple3;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat();
    _rippleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

    _logoController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _textController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeIn)), weight: 30),
    ]).animate(_logoController);

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _logoController, curve: const Interval(0, 0.5, curve: Curves.easeOut)),
    );

    _logoRotate = Tween<double>(begin: -0.15, end: 0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    _titleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: const Interval(0, 0.6, curve: Curves.easeOut)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _textController, curve: const Interval(0, 0.6, curve: Curves.easeOutCubic)),
    );
    _subtitleFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: const Interval(0.3, 0.9, curve: Curves.easeOut)),
    );
    _subtitleSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _textController, curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic)),
    );
    _loaderFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _textController, curve: const Interval(0.6, 1.0, curve: Curves.easeOut)),
    );

    _ripple1 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rippleController, curve: const Interval(0.0, 0.7, curve: Curves.easeOut)),
    );
    _ripple2 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rippleController, curve: const Interval(0.2, 0.9, curve: Curves.easeOut)),
    );
    _ripple3 = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _rippleController, curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
    );

    _logoController.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _textController.forward();
      });
    });

    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    });
  }

  @override
  void dispose() {
    _bgController.dispose();
    _logoController.dispose();
    _textController.dispose();
    _particleController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (_, __) {
          final t = _bgController.value;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(
                  math.cos(t * 2 * math.pi) * 0.9,
                  math.sin(t * 2 * math.pi) * 0.9,
                ),
                end: Alignment(
                  -math.cos(t * 2 * math.pi) * 0.9,
                  -math.sin(t * 2 * math.pi) * 0.9,
                ),
                colors: const [
                  Color(0xFF0D0020),
                  Color(0xFF4A0050),
                  Color(0xFFAA003B),
                  Color(0xFF220040),
                ],
                stops: const [0.0, 0.3, 0.7, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Floating particles
                for (int i = 0; i < 8; i++)
                  _SplashParticle(index: i, controller: _particleController, size: size),

                // Ripple rings behind logo
                Center(
                  child: AnimatedBuilder(
                    animation: _rippleController,
                    builder: (_, __) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          _buildRipple(_ripple1.value, 120),
                          _buildRipple(_ripple2.value, 120),
                          _buildRipple(_ripple3.value, 120),
                        ],
                      );
                    },
                  ),
                ),

                // Main content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      AnimatedBuilder(
                        animation: _logoController,
                        builder: (_, __) {
                          return FadeTransition(
                            opacity: _logoFade,
                            child: Transform.scale(
                              scale: _logoScale.value,
                              child: Transform.rotate(
                                angle: _logoRotate.value,
                                child: _buildLogo(),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 44),

                      // CRUX title
                      AnimatedBuilder(
                        animation: _textController,
                        builder: (_, __) {
                          return Column(
                            children: [
                              FadeTransition(
                                opacity: _titleFade,
                                child: SlideTransition(
                                  position: _titleSlide,
                                  child: ShaderMask(
                                    shaderCallback: (bounds) {
                                      return const LinearGradient(
                                        colors: [Color(0xFFFF4081), Colors.white, Color(0xFFAA00FF)],
                                      ).createShader(bounds);
                                    },
                                    child: Text(
                                      'CRUX',
                                      style: GoogleFonts.poppins(
                                        fontSize: 72,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 8,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              FadeTransition(
                                opacity: _subtitleFade,
                                child: SlideTransition(
                                  position: _subtitleSlide,
                                  child: Text(
                                    'Vidéoconférence Premium',
                                    style: GoogleFonts.poppins(
                                      fontSize: 15,
                                      color: Colors.white60,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 60),
                              FadeTransition(
                                opacity: _loaderFade,
                                child: _buildLoader(),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF4081), Color(0xFFAA00FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(42),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF4081).withValues(alpha: 0.6),
            blurRadius: 40,
            spreadRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFFAA00FF).withValues(alpha: 0.4),
            blurRadius: 60,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 76),
    );
  }

  Widget _buildRipple(double t, double baseRadius) {
    return Container(
      width: baseRadius + t * 160,
      height: baseRadius + t * 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFFF4081).withValues(alpha: (1 - t) * 0.3),
          width: 2,
        ),
      ),
    );
  }

  Widget _buildLoader() {
    return Column(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF4081)),
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Chargement...',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: Colors.white38,
            fontWeight: FontWeight.w400,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _SplashParticle extends StatelessWidget {
  final int index;
  final AnimationController controller;
  final Size size;

  const _SplashParticle({required this.index, required this.controller, required this.size});

  @override
  Widget build(BuildContext context) {
    final rng = math.Random(index * 17 + 3);
    final startX = rng.nextDouble() * size.width;
    final startY = rng.nextDouble() * size.height;
    final radius = 12.0 + rng.nextDouble() * 50;
    final phase = rng.nextDouble();

    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final t = (controller.value + phase) % 1.0;
        final dy = -size.height * 0.5 * t;
        final dx = math.sin(t * math.pi * 3) * 50;
        return Positioned(
          left: startX + dx,
          top: startY + dy,
          child: Opacity(
            opacity: (0.04 + rng.nextDouble() * 0.07) * (1 - t),
            child: Container(
              width: radius,
              height: radius,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index.isEven ? const Color(0xFFFF4081) : const Color(0xFFAA00FF),
              ),
            ),
          ),
        );
      },
    );
  }
}
