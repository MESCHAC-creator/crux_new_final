import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String _name = "CRUX";
  int _visibleLetters = 0;
  bool _showLine = false;
  bool _showSubtitle = false;

  @override
  void initState() {
    super.initState();
    _runAnimation();
  }

  Future<void> _runAnimation() async {
    // Typewriter effect: each letter appears with a delay
    for (int i = 1; i <= _name.length; i++) {
      await Future.delayed(const Duration(milliseconds: 120));
      if (mounted) setState(() => _visibleLetters = i);
    }

    // Line appearing after the last letter
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() => _showLine = true);

    // Subtitle appearing after the line
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _showSubtitle = true);

    // Final pause before proceeding
    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted) {
      _navigateAfterReady();
    }
  }

  Future<void> _navigateAfterReady() async {
    // Wait for Firebase Auth to restore persisted session
    final user = await FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 2),
      onTimeout: () => null,
    );

    if (!mounted) return;

    // If authenticated (non-anonymous), AuthWrapper in main.dart handles transition.
    // If not authenticated or anonymous, we navigate to the login screen.
    if (user == null || user.isAnonymous) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0E1A), Color(0xFF121624), Color(0xFF020205)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // New Premium Icon
              AnimatedOpacity(
                duration: const Duration(milliseconds: 800),
                opacity: _visibleLetters > 0 ? 1 : 0,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/icon.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              // CRUX Title with per-letter animation
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_name.length, (i) {
                  final visible = i < _visibleLetters;
                  return AnimatedSlide(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutBack,
                    offset: visible ? Offset.zero : const Offset(0, 0.4),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 400),
                      opacity: visible ? 1 : 0,
                      child: Text(
                        _name[i],
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              // Thin line with premium electric neon cyan color
              AnimatedOpacity(
                duration: const Duration(milliseconds: 450),
                opacity: _showLine ? 1 : 0,
                child: Container(
                  width: 50,
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF7C5CFF)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Discreet subtitle
              AnimatedOpacity(
                duration: const Duration(milliseconds: 600),
                opacity: _showSubtitle ? 1 : 0,
                child: Text(
                  "INTELLIGENT VIDEO CONFERENCING",
                  style: GoogleFonts.spaceGrotesk(
                    color: const Color(0xFF8A8FA3),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
