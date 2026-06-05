import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/premium_colors.dart';

class MeetingChat extends StatefulWidget {
  final String meetingId;

  const MeetingChat({Key? key, required this.meetingId}) : super(key: key);

  @override
  State<MeetingChat> createState() => _MeetingChatState();
}

class _MeetingChatState extends State<MeetingChat> {
  late TextEditingController _messageController;
  final _db = FirebaseFirestore.instance;
  String _userName = 'You';

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
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    _db
        .collection('meetings')
        .doc(widget.meetingId)
        .collection('chat')
        .add({
      'sender': _userName,
      'message': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
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

          // Messages (live from Firestore)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('meetings')
                  .doc(widget.meetingId)
                  .collection('chat')
                  .orderBy('timestamp', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (ctx, snap) {
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text('No messages yet',
                        style: GoogleFonts.poppins(
                            color: PremiumColors.textTertiary, fontSize: 12)),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data()! as Map<String, dynamic>;
                    return _ChatMessageWidget(
                      message: ChatMessage(
                        sender: d['sender'] ?? '?',
                        message: d['message'] ?? '',
                        timestamp: (d['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        isSystem: d['isSystem'] == true,
                      ),
                      isMine: d['sender'] == _userName,
                    );
                  },
                );
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
  final bool isMine;

  const _ChatMessageWidget({required this.message, this.isMine = false});

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
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMine
                ? PremiumColors.flamePrimary
                : PremiumColors.textSecondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMine)
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
                  color: isMine
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
