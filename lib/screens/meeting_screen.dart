import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/meeting_service.dart';
import '../theme/colors.dart';
import '../widgets/elegant_toast.dart';
import 'large_conference_screen.dart';

class MeetingScreen extends StatefulWidget {
  final String meetingId;
  final String meetingName;
  final String userId;
  final String userName;
  final String? userEmail;
  final bool isHost;

  const MeetingScreen({
    super.key,
    required this.meetingId,
    required this.meetingName,
    required this.userId,
    required this.userName,
    this.userEmail,
    this.isHost = false,
  });

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final MeetingService _meetingService = MeetingService();

  bool _preparing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // Utiliser le backend server pour ajouter le participant
      await _addParticipantViaBackend(widget.meetingId);

      if (widget.isHost) {
        await _meetingService.updateMeetingStatus(
          widget.meetingId,
          MeetingStatus.ongoing,
        );
      }

      if (mounted) {
        setState(() {
          _preparing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _addParticipantViaBackend(String meetingId) async {
    try {
      // Utiliser Firebase UID comme identité LiveKit
      final firebaseUid = FirebaseAuth.instance.currentUser?.uid;
      if (firebaseUid == null || firebaseUid.isEmpty) {
        throw Exception('Authentification Firebase requise');
      }

      // Ajouter le participant via Firestore direct
      await _meetingService.addParticipant(meetingId, firebaseUid);
    } catch (e) {
      throw Exception('Erreur ajout participant: $e');
    }
  }

  void _copyId() {
    Clipboard.setData(ClipboardData(text: widget.meetingId));

    ElegantToast.show(
      context,
      title: 'Succès',
      message: 'ID de la réunion copié dans le presse-papiers.',
      type: ElegantToastType.success,
    );
  }

  void _joinCall() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => LargeConferenceScreen(
              meetingId: widget.meetingId,
              meetingName: widget.meetingName,
              userId: widget.userId,
              userName: widget.userName,
              userEmail: widget.userEmail,
              isHost: widget.isHost,
            ),
      ),
    ).then((_) async {
      await _meetingService.removeParticipant(widget.meetingId, widget.userId);

      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child:
            _preparing
                ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                )
                : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 52),
            const SizedBox(height: 20),
            const Text(
              'Impossible de préparer la réunion',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppColors.radiusButton),
                  ),
                ),
                child: const Text('Retour'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          _buildMeetingCard(),
          const Spacer(),
          _buildStartButton(),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Annuler',
              style: TextStyle(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.meetingName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMeetingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.videocam_outlined,
              color: AppColors.textOnPrimary,
              size: 30,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Réunion sécurisée',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Audio et vidéo via LiveKit avec transport WebRTC sécurisé.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          InkWell(
            onTap: _copyId,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.tag,
                    color: AppColors.textTertiary,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.meetingId,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.copy_outlined,
                    color: AppColors.textTertiary,
                    size: 15,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _joinCall,
        icon: const Icon(Icons.videocam_outlined),
        label: const Text(
          "DÉMARRER L'APPEL",
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .3),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusButton),
          ),
        ),
      ),
    );
  }
}
