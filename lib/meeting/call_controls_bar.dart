import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../l10n/app_translations.dart';
import '../providers/locale_provider.dart';
import '../wallpaper/glass_surface.dart';

/// Action secondaire pour la bottom sheet.
class SecondaryAction {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onClick;

  const SecondaryAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onClick,
  });
}

/// Barre de contrôles d'appel CRUX.
/// 5 actions visibles, le reste dans une bottom sheet.
/// Réponse directe au « feature bloat » de Zoom.
class CallControlsBar extends StatefulWidget {
  final bool micEnabled;
  final bool cameraEnabled;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onShareScreen;
  final VoidCallback onOpenChat;
  final VoidCallback onLeave;
  final List<SecondaryAction> secondaryActions;

  const CallControlsBar({
    super.key,
    required this.micEnabled,
    required this.cameraEnabled,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onShareScreen,
    required this.onOpenChat,
    required this.onLeave,
    required this.secondaryActions,
  });

  @override
  State<CallControlsBar> createState() => _CallControlsBarState();
}

class _CallControlsBarState extends State<CallControlsBar> {
  bool _moreOpen = false;

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final t = AppTranslations.of(context);

    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ControlButton(
              icon: widget.micEnabled ? Icons.mic : Icons.mic_off,
              description: widget.micEnabled
                  ? (t.get('mute', lang) ?? 'Couper le micro')
                  : (t.get('unmute', lang) ?? 'Activer le micro'),
              active: !widget.micEnabled,
              onTap: widget.onToggleMic,
            ),
            _ControlButton(
              icon: widget.cameraEnabled ? Icons.videocam : Icons.videocam_off,
              description: widget.cameraEnabled
                  ? (t.get('stop_video', lang) ?? 'Couper la caméra')
                  : (t.get('start_video', lang) ?? 'Activer la caméra'),
              active: !widget.cameraEnabled,
              onTap: widget.onToggleCamera,
            ),
            _ControlButton(
              icon: Icons.screen_share,
              description: t.get('share_screen', lang) ?? 'Partager l\'écran',
              onTap: widget.onShareScreen,
            ),
            _ControlButton(
              icon: Icons.chat,
              description: t.get('open_chat', lang) ?? 'Ouvrir la discussion',
              onTap: widget.onOpenChat,
            ),
            _ControlButton(
              icon: Icons.more_horiz,
              description: t.get('more_options', lang) ?? 'Plus d\'options',
              onTap: () => setState(() => _moreOpen = true),
            ),
            const SizedBox(width: 8),
            // Quitter : seul bouton rouge rempli, impossible à confondre
            ElevatedButton(
              onPressed: widget.onLeave,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 48),
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String description;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.description,
    this.active = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              active ? AppColors.error : AppColors.surface.withOpacity(0.8),
          foregroundColor: active ? Colors.white : AppColors.textSecondary,
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
          elevation: 0,
        ),
        child: Icon(icon),
      ),
    );
  }
}
