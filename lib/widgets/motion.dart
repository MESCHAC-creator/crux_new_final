// lib/widgets/motion.dart
//
// Boîte à outils « motion design » de CRUX.
//
// Objectif : rendre l'app vivante SANS effets brillants (pas de halo, pas de
// dégradé, pas d'ombre lumineuse). Le mouvement remplace le brillant :
//   * PressableScale  → toute touche (Créer, Rejoindre, Planifier…) s'enfonce
//     légèrement au doigt, comme dans Zoom / iOS.
//   * FadeSlideIn     → apparition en cascade des blocs à l'ouverture.
//   * PulseDot        → point « en direct » qui respire (seul élément animé
//     en boucle, pour ne pas fatiguer l'œil).
//
// Aucune dépendance externe : uniquement flutter/material.

import 'package:flutter/material.dart';

/// Enveloppe une zone tactile : légère réduction d'échelle pendant l'appui.
/// Utilisable autour d'un bouton, d'une carte ou d'une tuile de réunion.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.duration = const Duration(milliseconds: 110),
    this.borderRadius,
    this.enableFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final BorderRadius? borderRadius;
  final bool enableFeedback;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: enabled ? (_down ? 0.92 : 1.0) : 0.55,
          duration: widget.duration,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Apparition douce : fondu + petite translation verticale.
/// [delay] permet de créer une cascade (0 ms, 60 ms, 120 ms…).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.offset = 16,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Point « en direct » qui respire lentement (opacité + taille).
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.size = 7});

  final Color color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_c.value);
        return Container(
          width: widget.size + t * 2,
          height: widget.size + t * 2,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.55 + t * 0.45),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
