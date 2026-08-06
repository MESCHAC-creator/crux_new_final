import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/colors.dart';
import '../l10n/app_translations.dart';
import '../providers/locale_provider.dart';
import 'meeting_state.dart';
import '../wallpaper/glass_surface.dart';

/// Panel de chat CRUX avec messages de groupe et DM 1-à-1.
/// Absents de Meet, implémentés via publishData avec destinataires ciblés.
class ChatPanel extends StatefulWidget {
  final List<ChatMessage> messages;
  final List<ParticipantUi> participants;
  final Function(String body, String? recipientSid) onSend;

  const ChatPanel({
    super.key,
    required this.messages,
    required this.participants,
    required this.onSend,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = TextEditingController();
  ParticipantUi? _recipient;

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final t = AppTranslations.of(context);

    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                itemCount: widget.messages.length,
                itemBuilder: (context, index) {
                  final msg =
                      widget.messages[widget.messages.length - 1 - index];
                  return _MessageBubble(message: msg);
                },
              ),
            ),
            const SizedBox(height: 8),
            // Sélecteur de destinataire
            ActionChip(
              avatar: const Icon(Icons.person, size: 18),
              label: Text(_recipient?.name ??
                  (t.get('everyone', lang) ?? 'À tout le monde')),
              onPressed: () => _showRecipientPicker(context),
              backgroundColor: AppColors.surface,
              labelStyle: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: t.get('message', lang) ?? 'Message',
                      hintStyle: TextStyle(color: AppColors.textSecondary),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _controller.text.isNotEmpty
                      ? () {
                          widget.onSend(
                              _controller.text.trim(), _recipient?.sid);
                          _controller.clear();
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    shape: const CircleBorder(),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRecipientPicker(BuildContext context) {
    final lang = context.read<LocaleProvider>().locale.languageCode;
    final t = AppTranslations.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                t.get('everyone', lang) ?? 'Tout le monde',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                setState(() => _recipient = null);
                Navigator.pop(context);
              },
            ),
            ...widget.participants.where((p) => !p.isLocal).map((p) => ListTile(
                  title: Text(
                    p.name,
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    t.get('private_message', lang) ?? 'Message privé',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  onTap: () {
                    setState(() => _recipient = p);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isPrivate = message.isPrivate;
    return Align(
      alignment: message.fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            message.fromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            '${message.senderName}${isPrivate ? ' · privé' : ''}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: message.fromMe
                  ? AppColors.primary.withOpacity(0.3)
                  : isPrivate
                      ? AppColors.secondary.withOpacity(0.3)
                      : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              message.body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary,
                  ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
