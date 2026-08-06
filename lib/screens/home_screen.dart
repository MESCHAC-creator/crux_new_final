// lib/screens/home_screen.dart
// Design mobile-first : bottom nav 4 onglets, palette Obsidian + Cyan,
// même ADN visuel que le splash screen

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../models/user_model.dart';
import '../models/meeting_model.dart';
import '../providers/locale_provider.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/pro_service.dart';
import '../services/notification_service.dart';
import '../theme/colors.dart';
import '../utils/logger.dart' as crux;
import '../widgets/elegant_toast.dart';
import 'create_meeting_screen.dart';
import 'join_meeting_screen.dart';
import 'setting_screen.dart';
import 'pro_screen.dart';
import 'profile_screen.dart';
import 'large_conference_screen.dart';
import 'meeting_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  bool _isPro = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    // Forcer la status bar transparente (même que splash)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _checkPro();
    NotificationService().initialize();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkPro() async {
    try {
      final p = await ProService().checkProStatus(widget.user.uid);
      if (mounted) setState(() => _isPro = p);
    } catch (_) {}
  }

  void _switchTab(int index) {
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      _AccueilTab(user: widget.user, isPro: _isPro),
      _ReunionsTab(user: widget.user),
      const _ChatTab(),
      _ProfilTab(user: widget.user, isPro: _isPro),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: tabs[_currentIndex],
      ),
      bottomNavigationBar: _CruxBottomNav(
        currentIndex: _currentIndex,
        onTap: _switchTab,
        isPro: _isPro,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// BOTTOM NAVIGATION — style Zoom
// ════════════════════════════════════════════════════════════════

class _CruxBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isPro;

  const _CruxBottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.isPro,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Accueil',
                index: 0,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.video_call_outlined,
                activeIcon: Icons.video_call_rounded,
                label: 'Réunions',
                index: 1,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.chat_bubble_outline_rounded,
                activeIcon: Icons.chat_bubble_rounded,
                label: 'Chat',
                index: 2,
                currentIndex: currentIndex,
                onTap: onTap,
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profil',
                index: 3,
                currentIndex: currentIndex,
                onTap: onTap,
                badge: isPro ? 'PRO' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final String? badge;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == currentIndex;

    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: 48,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.primaryWithOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    isActive ? activeIcon : icon,
                    size: 24,
                    color: isActive ? AppColors.primary : AppColors.textTertiary,
                  ),
                ),
                if (badge != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.proBadge,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge!,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: isActive ? AppColors.primary : AppColors.textTertiary,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ONGLET 1 — ACCUEIL
// ════════════════════════════════════════════════════════════════

class _AccueilTab extends StatelessWidget {
  final UserModel user;
  final bool isPro;

  const _AccueilTab({required this.user, required this.isPro});

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  String get _firstName => user.name.split(' ').first;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [

          // ── Header (même logique visuelle que splash) ────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_greeting,',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _firstName,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                  letterSpacing: -0.5,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isPro) ...[
                              const SizedBox(width: 8),
                              const _ProBadge(),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Avatar avec même style que le logo du splash
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: user.profileImageUrl?.isNotEmpty == true
                            ? null
                            : AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        image: user.profileImageUrl?.isNotEmpty == true
                            ? DecorationImage(
                                image: NetworkImage(user.profileImageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: user.profileImageUrl?.isNotEmpty != true
                          ? Center(
                              child: Text(
                                user.name.isNotEmpty
                                    ? user.name[0].toUpperCase()
                                    : '?',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textOnPrimary,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Hero : bouton principal "Nouvelle réunion" ───────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: _NewMeetingHero(context: context),
            ),
          ),

          // ── Actions secondaires (3 colonnes) ────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.login_rounded,
                      label: 'Rejoindre',
                      color: AppColors.secondary,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const JoinMeetingScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.calendar_today_rounded,
                      label: 'Planifier',
                      color: const Color(0xFF7C3AED),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const CreateMeetingScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.screen_share_rounded,
                      label: 'Partager',
                      color: AppColors.success,
                      onTap: () => Share.share(
                        'Rejoins-moi sur CRUX : https://crux-3c6be.web.app',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Section : Prochaines réunions ────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'À venir',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: AppColors.background,
                          body: _ReunionsTab(user: user, showBackButton: true),
                        ),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Tout voir',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          _UpcomingSliver(userId: FirebaseAuth.instance.currentUser!.uid),

          // ── Section : Réunions récentes ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
              child: Text(
                'Récentes',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),

          _RecentSliver(userId: FirebaseAuth.instance.currentUser!.uid),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ── Hero "Nouvelle réunion" — logo + gradient identique au splash ────────
class _NewMeetingHero extends StatelessWidget {
  final BuildContext context;
  const _NewMeetingHero({required this.context});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CreateMeetingScreen()),
      ),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF00E5FF), Color(0xFF00B8D4)],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Cercle décoratif (clin d'œil au logo splash)
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 20,
              bottom: -30,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Contenu
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                children: [
                  // Icône — même style conteneur que splash
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Nouvelle réunion',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Démarrer instantanément',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Badge PRO compact (à côté du prénom) ──────────────────────────────────
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.proBadgeSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.proBadge.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded, color: AppColors.proBadge, size: 12),
          const SizedBox(width: 3),
          Text(
            'PRO',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: AppColors.proBadge,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte d'action rapide (Rejoindre / Planifier / Partager) ─────────────
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// LISTES DE RÉUNIONS — flux Firestore partagés (Accueil + onglet Réunions)
// ════════════════════════════════════════════════════════════════

/// Ouvre la réunion adaptée (SFU grande conférence ou P2P standard).
void _openMeeting(BuildContext context, MeetingModel meeting, String userId) {
  final fb = FirebaseAuth.instance.currentUser;
  final userName = fb?.displayName?.trim().isNotEmpty == true
      ? fb!.displayName!
      : (fb?.email?.split('@').first ?? 'Utilisateur');

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => meeting.isLargeConference
          ? LargeConferenceScreen(
              meetingId: meeting.id,
              meetingName: meeting.title,
              userId: userId,
              userName: userName,
            )
          : MeetingScreen(
              meetingId: meeting.id,
              meetingName: meeting.title,
              userId: userId,
              userName: userName,
              userEmail: fb?.email,
              isHost: meeting.organizerId == userId,
            ),
    ),
  );
}

MeetingModel _meetingFromDoc(QueryDocumentSnapshot doc) {
  return MeetingModel.fromJson({
    ...doc.data() as Map<String, dynamic>,
    'id': doc.id,
  });
}

class _UpcomingSliver extends StatelessWidget {
  final String userId;
  const _UpcomingSliver({required this.userId});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: StreamBuilder<QuerySnapshot>(
          // ⚠️ Nécessite un index composite Firestore (participants + status + startTime).
          // Au premier lancement, Firestore fournit un lien direct dans les logs pour le créer.
          stream: FirebaseFirestore.instance
              .collection('meetings')
              .where('participants', arrayContains: userId)
              .where('status', isEqualTo: 'scheduled')
              .orderBy('startTime')
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _MeetingsLoading();
            }
            if (snapshot.hasError) {
              crux.logger.w('UpcomingSliver error', error: snapshot.error);
              return const _MeetingsEmpty(
                icon: Icons.event_busy_rounded,
                message: 'Impossible de charger les réunions à venir',
              );
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const _MeetingsEmpty(
                icon: Icons.event_available_rounded,
                message: 'Aucune réunion planifiée',
              );
            }
            return Column(
              children: docs.map((d) {
                final meeting = _meetingFromDoc(d);
                return _MeetingCard(
                  meeting: meeting,
                  onTap: () => _openMeeting(context, meeting, userId),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _RecentSliver extends StatelessWidget {
  final String userId;
  const _RecentSliver({required this.userId});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('meetings')
              .where('participants', arrayContains: userId)
              .where('status', isEqualTo: 'ended')
              .orderBy('startTime', descending: true)
              .limit(5)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _MeetingsLoading();
            }
            if (snapshot.hasError) {
              crux.logger.w('RecentSliver error', error: snapshot.error);
              return const _MeetingsEmpty(
                icon: Icons.history_rounded,
                message: 'Impossible de charger l\'historique',
              );
            }
            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const _MeetingsEmpty(
                icon: Icons.history_rounded,
                message: 'Aucune réunion récente',
              );
            }
            return Column(
              children: docs.map((d) {
                final meeting = _meetingFromDoc(d);
                return _MeetingCard(
                  meeting: meeting,
                  onTap: () => _openMeeting(context, meeting, userId),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}

class _MeetingsLoading extends StatelessWidget {
  const _MeetingsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        ),
      ),
    );
  }
}

class _MeetingsEmpty extends StatelessWidget {
  final IconData icon;
  final String message;
  const _MeetingsEmpty({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 26),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final MeetingModel meeting;
  final VoidCallback onTap;

  const _MeetingCard({required this.meeting, required this.onTap});

  static const _months = [
    'Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Juin',
    'Juil', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc',
  ];

  // Formatage manuel — évite DateFormat(locale: 'fr_FR') qui lève une
  // LocaleDataException tant que initializeDateFormatting() n'a pas été
  // appelé dans main() (non fait actuellement dans le projet).
  String _dateLabel(DateTime d, {required bool withTime}) {
    final base = '${d.day} ${_months[d.month - 1]}';
    if (!withTime) return base;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$base · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isEnded = meeting.status == MeetingStatus.ended;
    final dateLabel = _dateLabel(
      meeting.startTime,
      withTime: meeting.status == MeetingStatus.scheduled,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isEnded
                    ? AppColors.textDisabled.withOpacity(0.15)
                    : AppColors.primaryWithOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                meeting.isLargeConference ? Icons.groups_rounded : Icons.videocam_rounded,
                color: isEnded ? AppColors.textTertiary : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meeting.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateLabel,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (!isEnded)
              IconButton(
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                color: AppColors.textTertiary,
                onPressed: () => Share.share(
                  'Rejoins ma réunion CRUX "${meeting.title}" avec le code : ${meeting.id}',
                ),
              )
            else
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ONGLET 2 — RÉUNIONS (liste complète, filtrable)
// ════════════════════════════════════════════════════════════════

class _ReunionsTab extends StatefulWidget {
  final UserModel user;
  final bool showBackButton;
  const _ReunionsTab({required this.user, this.showBackButton = false});

  @override
  State<_ReunionsTab> createState() => _ReunionsTabState();
}

class _ReunionsTabState extends State<_ReunionsTab> {
  bool _showUpcoming = true;

  @override
  Widget build(BuildContext context) {
    final userId = widget.user.uid;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (widget.showBackButton) ...[
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: AppColors.textPrimary, size: 20),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Text(
                      'Réunions',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary, size: 28),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateMeetingScreen()),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: _FilterChip(
                    label: 'À venir',
                    selected: _showUpcoming,
                    onTap: () => setState(() => _showUpcoming = true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilterChip(
                    label: 'Terminées',
                    selected: !_showUpcoming,
                    onTap: () => setState(() => _showUpcoming = false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('meetings')
                  .where('participants', arrayContains: userId)
                  .where('status', isEqualTo: _showUpcoming ? 'scheduled' : 'ended')
                  .orderBy('startTime', descending: !_showUpcoming)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }
                if (snapshot.hasError) {
                  crux.logger.w('ReunionsTab stream error', error: snapshot.error);
                  return Center(
                    child: Text(
                      'Impossible de charger vos réunions',
                      style: GoogleFonts.spaceGrotesk(color: AppColors.textTertiary),
                    ),
                  );
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showUpcoming ? Icons.event_available_rounded : Icons.history_rounded,
                          color: AppColors.textTertiary,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _showUpcoming ? 'Aucune réunion planifiée' : 'Aucune réunion récente',
                          style: GoogleFonts.spaceGrotesk(color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final meeting = _meetingFromDoc(docs[i]);
                    return _MeetingCard(
                      meeting: meeting,
                      onTap: () => _openMeeting(context, meeting, userId),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryWithOpacity(0.15) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ONGLET 3 — CHAT (fonctionnalité à venir — aucun backend messagerie
// n'existe encore dans le projet ; onglet volontairement en attente)
// ════════════════════════════════════════════════════════════════

class _ChatTab extends StatelessWidget {
  const _ChatTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chat',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.textTertiary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bientôt disponible',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La messagerie CRUX arrive prochainement',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// ONGLET 4 — PROFIL
// ════════════════════════════════════════════════════════════════

class _ProfilTab extends StatelessWidget {
  final UserModel user;
  final bool isPro;

  const _ProfilTab({required this.user, required this.isPro});

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Se déconnecter', style: GoogleFonts.spaceGrotesk(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await AuthService().signOut();
      } catch (e) {
        crux.logger.e('SignOut error', error: e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Profil',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // ── Carte identité ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: user.profileImageUrl?.isNotEmpty == true
                        ? null
                        : AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    image: user.profileImageUrl?.isNotEmpty == true
                        ? DecorationImage(
                            image: NetworkImage(user.profileImageUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: user.profileImageUrl?.isNotEmpty != true
                      ? Center(
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textOnPrimary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isPro) ...[
                            const SizedBox(width: 8),
                            const _ProBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (!isPro)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.proBadgeSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.proBadge.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: AppColors.proBadge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Passer à CRUX PRO',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.proBadge,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.proBadge),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          _ProfileMenuTile(
            icon: Icons.person_outline_rounded,
            label: 'Modifier le profil',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          _ProfileMenuTile(
            icon: Icons.settings_outlined,
            label: 'Paramètres',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          _ProfileMenuTile(
            icon: Icons.logout_rounded,
            label: 'Se déconnecter',
            danger: true,
            onTap: () => _confirmSignOut(context),
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : AppColors.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? AppColors.error : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (!danger)
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
