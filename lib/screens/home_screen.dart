// lib/screens/home_screen.dart
//
// Accueil CRUX — direction « Flat Meeting » (esprit Zoom) :
//   * PLUS AUCUN effet brillant : pas de dégradé, pas de halo lumineux,
//     pas d'ombre colorée. Uniquement des aplats + un filet de bordure 1 px.
//   * Le relief vient du MOUVEMENT, pas de la lumière : chaque touche
//     (Démarrer, Planifier, Rejoindre, code, tuiles) s'enfonce à l'appui,
//     les blocs entrent en cascade, le badge « en direct » respire.
//
// Correctifs fonctionnels conservés :
//   * « Planifier » ouvre AppRoutes.schedule ;
//   * réunions à venir via ScheduleService.streamUpcoming() ;
//   * rappels locaux resynchronisés à l'ouverture.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/meeting_model.dart';
import '../models/user_model.dart';
import '../providers/wallpaper_provider.dart';
import '../routes/app_routes.dart';
import '../services/schedule_service.dart';
import '../theme/colors.dart';
import '../widgets/motion.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _schedule = ScheduleService();
  final _codeCtrl = TextEditingController();
  final FocusNode _codeFocus = FocusNode();

  String get _uid => widget.user.uid.isNotEmpty
      ? widget.user.uid
      : (FirebaseAuth.instance.currentUser?.uid ?? '');

  String get _displayName =>
      widget.user.name.trim().isNotEmpty ? widget.user.name.trim() : 'Bienvenue';

  @override
  void initState() {
    super.initState();
    _codeCtrl.addListener(() => setState(() {}));
    // Les notifications locales sont perdues après un redémarrage système :
    // on les reprogramme à l'ouverture de l'accueil.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_uid.isNotEmpty) _schedule.resyncReminders(userId: _uid);
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ actions

  void _openSchedule() => Navigator.of(context).pushNamed(AppRoutes.schedule);

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
          content:
              Text(message, style: const TextStyle(color: AppColors.textPrimary)),
          backgroundColor: AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ----------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    // Fond utilisateur = accueil transparent. Sinon aplat sobre (aucun dégradé).
    final hasWallpaper = context.watch<WallpaperProvider>().hasCustomImage;

    return Scaffold(
      backgroundColor: hasWallpaper ? Colors.transparent : AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              FadeSlideIn(child: _header()),
              const SizedBox(height: 24),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: _actionsBlock(),
              ),
              const SizedBox(height: 14),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: _joinRow(),
              ),
              const SizedBox(height: 30),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: _sectionHeader('À venir'),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 220),
                child: _upcoming(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final initials = _displayName.trim().isEmpty
        ? 'C'
        : _displayName
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((w) => w[0])
            .join()
            .toUpperCase();

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
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        _iconAction(
          icon: Icons.image_outlined,
          tooltip: 'Fond d\'écran',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.wallpaper),
        ),
        const SizedBox(width: 4),
        _iconAction(
          icon: Icons.settings_outlined,
          tooltip: 'Réglages',
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
        ),
        const SizedBox(width: 8),
        PressableScale(
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              // Aplat, pas de dégradé : rendu mat type Zoom.
              color: AppColors.surfaceVariant,
              shape: BoxShape.circle,
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

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        onTap: onTap,
        scale: 0.9,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: AppColors.textSecondary, size: 22),
        ),
      ),
    );
  }

  /// Bloc d'actions à la Zoom : quatre tuiles carrées, mates, sans bordure
  /// brillante. Toute l'animation est dans la pression du doigt.
  Widget _actionsBlock() {
    return Row(
      children: [
        Expanded(
          child: _actionTile(
            icon: Icons.videocam_rounded,
            label: 'Nouvelle\nréunion',
            filled: true,
            onTap: _startInstant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionTile(
            icon: Icons.add_box_outlined,
            label: 'Rejoindre',
            onTap: () => FocusScope.of(context).requestFocus(_codeFocus),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _actionTile(
            icon: Icons.event_outlined,
            label: 'Planifier',
            onTap: _openSchedule,
          ),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 104,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: AppColors.borderSubtle, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 26,
              color: filled ? AppColors.textOnPrimary : AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.2,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color:
                    filled ? AppColors.textOnPrimary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _joinRow() {
    final hasCode = _codeCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderSubtle, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              focusNode: _codeFocus,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _joinByCode(),
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              style:
                  const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              cursorColor: AppColors.primary,
              decoration: const InputDecoration(
                hintText: 'Entrer un code de réunion',
                hintStyle:
                    TextStyle(color: AppColors.textDisabled, fontSize: 14),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
          ),
          // Le bouton se révèle en douceur dès qu'un code est saisi.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: hasCode ? 1 : 0.35,
              duration: const Duration(milliseconds: 220),
              child: PressableScale(
                onTap: hasCode ? _joinByCode : null,
                scale: 0.92,
                child: Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: hasCode
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Rejoindre',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: hasCode
                          ? AppColors.textOnPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
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
              letterSpacing: 1.2,
            ),
          ),
          PressableScale(
            onTap: _openSchedule,
            scale: 0.94,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text('Nouvelle',
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          ),
        ],
      );

  Widget _upcoming() {
    if (_uid.isEmpty) return _empty('Connectez-vous pour voir vos réunions.');
    return StreamBuilder<List<MeetingModel>>(
      stream: _schedule.streamUpcoming(userId: _uid),
      builder: (context, snapshot) {
        Widget content;
        if (snapshot.connectionState == ConnectionState.waiting) {
          content = const Padding(
            key: ValueKey('loading'),
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
        } else if (snapshot.hasError) {
          content = _empty(
            'Impossible de charger vos réunions.\n'
            'Vérifiez l\'index Firestore meetings(participants, status, startTime).',
          );
        } else {
          final meetings = snapshot.data ?? const <MeetingModel>[];
          content = meetings.isEmpty
              ? _empty('Aucune réunion planifiée.')
              : Column(
                  key: ValueKey('list-${meetings.length}'),
                  children: [
                    for (var i = 0; i < meetings.length; i++)
                      FadeSlideIn(
                        delay: Duration(milliseconds: 50 * i),
                        offset: 12,
                        child: _meetingTile(meetings[i]),
                      ),
                  ],
                );
        }
        // Transition douce entre chargement / vide / liste.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: content,
        );
      },
    );
  }

  Widget _meetingTile(MeetingModel meeting) {
    final live = meeting.status == MeetingStatus.ongoing;
    return PressableScale(
      onTap: meeting.isJoinable ? () => _joinMeeting(meeting) : null,
      scale: 0.985,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(10),
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
                            color: AppColors.liveWithOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              PulseDot(color: AppColors.liveDot, size: 6),
                              SizedBox(width: 6),
                              Text(
                                'EN DIRECT',
                                style: TextStyle(
                                  color: AppColors.liveDot,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
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
            PressableScale(
              onTap: meeting.isJoinable ? () => _joinMeeting(meeting) : null,
              scale: 0.92,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: meeting.isJoinable
                      ? AppColors.primary
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Rejoindre',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: meeting.isJoinable
                        ? AppColors.textOnPrimary
                        : AppColors.textDisabled,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String message) => Container(
        key: ValueKey('empty-$message'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderSubtle, width: 1),
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
