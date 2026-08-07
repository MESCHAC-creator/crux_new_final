// lib/screens/home_screen.dart
//
// Accueil CRUX — direction « Obsidian Mono » : profond mais simple, couleurs
// tirées du logo (obsidienne + blanc/argent). Le cyan n'est plus décoratif :
// il ne sert qu'au badge « En direct ».
//
// CORRECTIFS fonctionnels :
//   * le bouton « Planifier » ouvre AppRoutes.schedule (avant : il lançait une
//     réunion instantanée) ;
//   * les réunions à venir sont lues via ScheduleService.streamUpcoming(),
//     donc exactement la requête que la planification alimente désormais
//     (collection `meetings`, participants arrayContains uid, status
//     'scheduled', orderBy startTime) ;
//   * les dates passent par MeetingModel/flexDate → un document en Timestamp
//     comme un ancien document en String ISO s'affichent tous les deux ;
//   * les rappels locaux sont resynchronisés au démarrage de l'écran.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meeting_model.dart';
import '../models/user_model.dart';
import '../routes/app_routes.dart';
import '../services/schedule_service.dart';
import '../theme/colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _schedule = ScheduleService();
  final _codeCtrl = TextEditingController();

  String get _uid =>
      widget.user.uid.isNotEmpty
          ? widget.user.uid
          : (FirebaseAuth.instance.currentUser?.uid ?? '');

  String get _displayName =>
      widget.user.name.trim().isNotEmpty ? widget.user.name.trim() : 'Bienvenue';

  @override
  void initState() {
    super.initState();
    // Les notifications locales sont perdues après un redémarrage système :
    // on les reprogramme à l'ouverture de l'accueil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_uid.isNotEmpty) _schedule.resyncReminders(userId: _uid);
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ actions

  void _openSchedule() {
    Navigator.of(context).pushNamed(AppRoutes.schedule);
  }

  void _startInstant() {
    final code = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    Navigator.of(context).pushNamed(
      AppRoutes.meeting,
      arguments: {
        'meetingId': code,
        'meetingName': 'Réunion instantanée',
        'userId': _uid,
        'userName': _displayName,
        'userEmail': widget.user.email,
        'isHost': true,
      },
    );
  }

  void _joinMeeting(MeetingModel meeting) {
    Navigator.of(context).pushNamed(
      AppRoutes.meeting,
      arguments: {
        'meetingId': meeting.id,
        'meetingName': meeting.title,
        'userId': _uid,
        'userName': _displayName,
        'userEmail': widget.user.email,
        'isHost': meeting.organizerId == _uid,
      },
    );
  }

  Future<void> _joinByCode() async {
    final code = _codeCtrl.text.trim().toLowerCase();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('meetings')
          .where('meetingCode', isEqualTo: code)
          .limit(1)
          .get();
      if (!mounted) return;
      if (snap.docs.isEmpty) {
        _snack('Aucune réunion pour ce code.');
        return;
      }
      final doc = snap.docs.first;
      _codeCtrl.clear();
      _joinMeeting(MeetingModel.fromDoc(doc.id, doc.data()));
    } catch (_) {
      if (mounted) _snack('Connexion impossible, réessayez.');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message,
              style: const TextStyle(color: AppColors.textPrimary)),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ----------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _header(),
                const SizedBox(height: 28),
                _heroCard(),
                const SizedBox(height: 16),
                _joinRow(),
                const SizedBox(height: 32),
                _sectionHeader('À venir'),
                const SizedBox(height: 12),
                _upcoming(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final initials = _displayName.trim().isEmpty
        ? 'C'
        : _displayName.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0]).join().toUpperCase();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting(),
                style: const TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Réglages',
          onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
          icon: const Icon(Icons.settings_outlined,
              color: AppColors.textSecondary),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
          child: Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.glassGradient,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Carte principale : le halo blanc évoque le logo laqué, sans couleur.
  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.logoHalo,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded,
                    color: AppColors.textPrimary, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Lancez ou planifiez\nune réunion',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _startInstant,
                  child: const Text('Démarrer',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  // CORRECTIF : route de planification (et non la réunion).
                  onPressed: _openSchedule,
                  child: const Text('Planifier',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _joinRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _joinByCode(),
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                hintText: 'Entrer un code de réunion',
                hintStyle:
                    TextStyle(color: AppColors.textDisabled, fontSize: 14),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
          IconButton(
            onPressed: _joinByCode,
            icon: const Icon(Icons.arrow_forward_rounded,
                color: AppColors.textPrimary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          TextButton(
            onPressed: _openSchedule,
            child: const Text('Nouvelle',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ),
        ],
      );

  Widget _upcoming() {
    if (_uid.isEmpty) return _empty('Connectez-vous pour voir vos réunions.');
    return StreamBuilder<List<MeetingModel>>(
      stream: _schedule.streamUpcoming(userId: _uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textSecondary),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _empty(
            'Impossible de charger vos réunions.\n'
            'Vérifiez l\'index Firestore meetings(participants, status, startTime).',
          );
        }
        final meetings = snapshot.data ?? const <MeetingModel>[];
        if (meetings.isEmpty) {
          return _empty('Aucune réunion planifiée.');
        }
        return Column(
          children: meetings.map(_meetingTile).toList(),
        );
      },
    );
  }

  Widget _meetingTile(MeetingModel meeting) {
    final live = meeting.status == MeetingStatus.ongoing;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  meeting.startTime.day.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _monthShort(meeting.startTime.month),
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meeting.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (live) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.liveWithOpacity(0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'EN DIRECT',
                          style: TextStyle(
                            color: AppColors.liveDot,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_time(meeting.startTime)} – ${_time(meeting.endTime)}'
                  '${meeting.participants.length > 1 ? ' · ${meeting.participants.length} participants' : ''}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: meeting.isJoinable
                  ? AppColors.textPrimary
                  : AppColors.textDisabled,
            ),
            onPressed: meeting.isJoinable ? () => _joinMeeting(meeting) : null,
            child: const Text('Rejoindre',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _empty(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          children: [
            const Icon(Icons.event_note_outlined,
                color: AppColors.textDisabled, size: 26),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------- formats

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'BONNE NUIT';
    if (h < 12) return 'BONJOUR';
    if (h < 18) return 'BON APRÈS-MIDI';
    return 'BONSOIR';
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _monthShort(int month) => const [
        'JAN', 'FÉV', 'MAR', 'AVR', 'MAI', 'JUIN',
        'JUIL', 'AOÛ', 'SEP', 'OCT', 'NOV', 'DÉC',
      ][month - 1];
}
