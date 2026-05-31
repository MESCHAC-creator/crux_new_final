import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/premium_colors.dart';

class MeetingChat extends StatefulWidget {
  final String meetingId;

  const MeetingChat({Key? key, required this.meetingId}) : super(key: key);

  @override
  State<MeetingChat> createState() => _MeetingChatState();
}

class _MeetingChatState extends State<MeetingChat> {
  late TextEditingController _messageController;
  final List<ChatMessage> _messages = [
    ChatMessage(
      sender: 'System',
      message: 'Meeting started',
      timestamp: DateTime.now(),
      isSystem: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    if (_messageController.text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          sender: 'You',
          message: _messageController.text,
          timestamp: DateTime.now(),
        ),
      );
    });

    _messageController.clear();
    // TODO: Send to Firestore
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PremiumColors.darkBackground,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: PremiumColors.borderGray.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Text(
              'Meeting Chat',
              style: GoogleFonts.poppins(
                color: PremiumColors.snowWhite,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (ctx, index) {
                final msg = _messages[_messages.length - 1 - index];
                return _ChatMessageWidget(message: msg);
              },
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: PremiumColors.borderGray.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: PremiumColors.snowWhite),
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: const TextStyle(
                        color: PremiumColors.textTertiary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: PremiumColors.borderGray,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: PremiumColors.flamePrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send,
                      color: PremiumColors.snowWhite,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessageWidget extends StatelessWidget {
  final ChatMessage message;

  const _ChatMessageWidget({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: PremiumColors.textSecondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              message.message,
              style: GoogleFonts.poppins(
                color: PremiumColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: message.sender == 'You' ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: message.sender == 'You'
                ? PremiumColors.flamePrimary
                : PremiumColors.textSecondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.sender != 'You')
                Text(
                  message.sender,
                  style: GoogleFonts.poppins(
                    color: PremiumColors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                message.message,
                style: GoogleFonts.poppins(
                  color: message.sender == 'You'
                      ? PremiumColors.snowWhite
                      : PremiumColors.textPrimary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String sender;
  final String message;
  final DateTime timestamp;
  final bool isSystem;

  ChatMessage({
    required this.sender,
    required this.message,
    required this.timestamp,
    this.isSystem = false,
  });
}
