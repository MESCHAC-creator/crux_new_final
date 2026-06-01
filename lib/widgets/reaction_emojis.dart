import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/premium_colors.dart';

class ReactionEmojis extends StatelessWidget {
  final Function(String emoji) onReactionSelected;

  const ReactionEmojis({
    Key? key,
    required this.onReactionSelected,
  }) : super(key: key);

  static const List<Map<String, String>> reactions = [
    {'emoji': '👍', 'label': 'Like'},
    {'emoji': '❤️', 'label': 'Love'},
    {'emoji': '😂', 'label': 'Funny'},
    {'emoji': '😮', 'label': 'Wow'},
    {'emoji': '👏', 'label': 'Clap'},
    {'emoji': '🙌', 'label': 'Celebrate'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PremiumColors.darkBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PremiumColors.borderGray.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            children: reactions.map((reaction) {
              return GestureDetector(
                onTap: () {
                  onReactionSelected(reaction['emoji']!);
                  Navigator.pop(context);
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PremiumColors.surfaceGray.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        reaction['emoji']!,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reaction['label']!,
                        style: const TextStyle(
                          color: PremiumColors.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              )
                  .animate()
                  .scale(duration: 300.ms);
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class FloatingReaction extends StatefulWidget {
  final String emoji;
  final Offset position;

  const FloatingReaction({
    Key? key,
    required this.emoji,
    required this.position,
  }) : super(key: key);

  @override
  State<FloatingReaction> createState() => _FloatingReactionState();
}

class _FloatingReactionState extends State<FloatingReaction> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx,
      top: widget.position.dy,
      child: Text(
        widget.emoji,
        style: const TextStyle(fontSize: 40),
      )
          .animate()
          .moveY(begin: 0, end: -100, duration: 3000.ms)
          .fadeOut(begin: 1, duration: 2500.ms),
    );
  }
}
