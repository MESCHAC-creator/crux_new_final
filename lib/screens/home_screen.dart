import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/meeting_model.dart';
import '../models/user_model.dart';
import '../wallpaper/wallpaper_provider.dart';
import '../routes/app_routes.dart';
import '../services/schedule_service.dart';
import '../theme/colors.dart';
import '../wallpaper/app_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.user});

  final UserModel user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _schedule = ScheduleService();
  final _codeCtrl = TextEditingController();
  int _selectedNav = 0;

  String get _uid =>
      widget.user.uid.isNotEmpty
          ? widget.user.uid
          : (FirebaseAuth.instance.currentUser?.uid ?? '');

  String get _displayName =>
      widget.user.name.trim().isNotEmpty ? widget.user.name.trim() : 'Bienvenue';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_uid.isNotEmpty) _schedule.resyncReminders(userId: _uid);
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
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

  void _handleNavigation(int index) {
    setState(() => _selectedNav = index);
    switch (index) {
      case 0: // Home
        break;
      case 1: // Meetings
        Navigator.of(context).pushNamed(AppRoutes.schedule);
        setState(() => _selectedNav = 0);
        break;
      case 2: // Settings
        Navigator.of(context).pushNamed(AppRoutes.settings);
        setState(() => _selectedNav = 0);
        break;
      case 3: // Profile
        Navigator.of(context).pushNamed(AppRoutes.profile);
        setState(() => _selectedNav = 0);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>().config;
    final screenWidth = MediaQuery.of(context).size.width;
    final useWideLayout = screenWidth >= 720;

    final content = SafeArea(
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
    );

    final body = wallpaper.hasImage
        ? AppBackground(config: wallpaper, child: content)
        : Container(
            decoration: const BoxDecoration(gradient: AppColors.heroGradient),
            child: content,
          );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: useWideLayout ? _buildWideLayout(body) : SafeArea(child: body),
      bottomNavigationBar: useWideLayout ? null : _buildBottomNavBar(),
    );
  }

  Widget _buildWideLayout(Widget body) {
    return Row(
      children: [
        // ── Material 3 NavigationRail (desktop/tablet) ────────────────
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              right: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
            ),
          ),
          child: SafeArea(
            right: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: NavigationRail(
                selectedIndex: _selectedNav,
                onDestinationSelected: _handleNavigation,
                extended: false,
                backgroundColor: Colors.transparent,
                elevation: 0,
                labelType: NavigationRailLabelType.all,
                indicatorColor: AppColors.primary.withOpacity(0.15),
                selectedIconTheme: const IconThemeData(
                  color: AppColors.primary,
                  size: 24,
                ),
                unselectedIconTheme: IconThemeData(
                  color: AppColors.textTertiary,
                  size: 22,
                ),
                selectedLabelTextStyle: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: Text('Accueil'),
                    padding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.event_outlined),
                    selectedIcon: Icon(Icons.event_rounded),
                    label: Text('Réunions'),
                    padding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    selectedIcon: Icon(Icons.settings_rounded),
                    label: Text('Param.'),
                    padding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person_rounded),
                    label: Text('Profil'),
                    padding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ],
                trailing: Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.video_call_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'CRUX',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // ── Contenu principal ────────────────────────────────────────
        Expanded(child: SafeArea(left: false, child: body)),
      ],
    );
  }

  Widget _buildBottomNavBar() {
    // ── Material 3 NavigationBar (mobile) ────────────────────────────
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: NavigationBar(
            selectedIndex: _selectedNav,
            onDestinationSelected: _handleNavigation,
            backgroundColor: Colors.transparent,
            elevation: 0,
            height: 64,
            indicatorColor: AppColors.primary.withOpacity(0.15),
            indicatorShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, size: 24),
                selectedIcon: Icon(Icons.home_rounded, size: 26),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_outlined, size: 24),
                selectedIcon: Icon(Icons.event_rounded, size: 26),
                label: 'Réunions',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined, size: 24),
                selectedIcon: Icon(Icons.settings_rounded, size: 26),
                label: 'Paramètres',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline, size: 24),
                selectedIcon: Icon(Icons.person_rounded, size: 26),
                label: 'Profil',
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
      ],
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lancer ou planifier une réunion',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _startInstant,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Démarrer',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      )),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.schedule),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Planifier',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      )),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Entrer un code de réunion',
                hintStyle: TextStyle(color: AppColors.textDisabled),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (_) => _joinByCode(),
            ),
          ),
          IconButton(
            onPressed: _joinByCode,
            icon: const Icon(Icons.arrow_forward,
                color: AppColors.textTertiary, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _upcoming() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('meetings')
          .where('participants', arrayContains: _uid)
          .where('endTime', isGreaterThan: Timestamp.now())
          .orderBy('endTime')
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation(AppColors.primary)));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return _empty('Aucune réunion à venir.');
        }
        return Column(
          children: snap.data!.docs
              .map((doc) => _meetingCard(
                  MeetingModel.fromDoc(doc.id, doc.data())))
              .toList(),
        );
      },
    );
  }

  Widget _meetingCard(MeetingModel meeting) {
    final live = meeting.endTime.isAfter(DateTime.now()) &&
        meeting.startTime.isBefore(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
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
            onPressed:
                meeting.isJoinable ? () => _joinMeeting(meeting) : null,
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

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 6) return 'BONNE NUIT';
    if (h < 12) return 'BONJOUR';
    if (h < 18) return 'BON APRÈS-MIDI';
    return 'BONSOIR';
  }

  String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
