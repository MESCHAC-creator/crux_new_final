import 'dart:async';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../providers/locale_provider.dart';
import '../providers/meeting_provider.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/notification_service.dart';
import '../services/device_verification_service.dart';
import '../services/pro_service.dart';
import '../utils/logger.dart' as crux;
import '../theme/colors.dart';
import '../widgets/elegant_toast.dart';
import 'create_meeting_screen.dart';
import 'join_meeting_screen.dart';
import 'meeting_history_screen.dart';
import 'settings_screen.dart';
import 'pro_screen.dart';
import 'meeting_screen.dart';
import 'large_conference_screen.dart';
import 'video_call_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isPro = false;
  List<Map<String, dynamic>> _meetings = [];
  List<Map<String, dynamic>> _history = [];
  int _meetingCount = 0;
  int _totalDuration = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _checkProStatus();
    _verifyDevice();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _verifyDevice() async {
    try {
      final deviceService = DeviceVerificationService();
      final isVerified = await deviceService.verifyDevice(widget.user.uid);
      if (!isVerified && mounted) {
        ElegantToast.show(
          context,
          title: 'Sécurité',
          message: 'Nouvel appareil détecté. Veuillez vérifier votre email.',
          type: ElegantToastType.warning,
        );
      }
    } catch (e) {
      crux.logger.w('Device verification error', error: e);
    }
  }

  Future<void> _checkProStatus() async {
    try {
      final isPro = await ProService().checkProStatus(widget.user.uid);
      if (mounted) setState(() => _isPro = isPro);
    } catch (e) {
      crux.logger.w('Pro status check error', error: e);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadMeetings(),
        _loadHistory(),
        _loadStats(),
      ]);
    } catch (e) {
      crux.logger.e('Error loading home data', error: e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMeetings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('meetings')
          .where('participants', arrayContains: widget.user.uid)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      final meetings = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Sans titre',
          'organizer': data['organizerName'] ?? 'Inconnu',
          'createdAt': data['createdAt'],
          'participantCount': (data['participants'] as List?)?.length ?? 0,
        };
      }).toList();

      if (mounted) setState(() => _meetings = meetings);
    } catch (e) {
      crux.logger.e('Error loading meetings', error: e);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('meeting_history')
          .orderBy('endedAt', descending: true)
          .limit(20)
          .get();

      final history = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Sans titre',
          'endedAt': data['endedAt'],
          'duration': data['duration'] ?? 0,
        };
      }).toList();

      if (mounted) setState(() => _history = history);
    } catch (e) {
      crux.logger.e('Error loading history', error: e);
    }
  }

  Future<void> _loadStats() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data();
        if (mounted) {
          setState(() {
            _meetingCount = data?['meetingCount'] ?? 0;
            _totalDuration = data?['totalDuration'] ?? 0;
          });
        }
      }
    } catch (e) {
      crux.logger.e('Error loading stats', error: e);
    }
  }

  String _displayName() {
    try {
      final fb = FirebaseAuth.instance.currentUser;
      if (fb?.displayName?.trim().isNotEmpty == true) return fb!.displayName!;
      if (fb?.email?.isNotEmpty == true && fb!.email!.contains('@'))
        return fb.email!.split('@')[0];
      return widget.user.name;
    } catch (e) {
      crux.logger.e('_displayName error', error: e);
      return 'Utilisateur';
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  void _showCreateMeetingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Nouvelle réunion',
            style: GoogleFonts.spaceGrotesk(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_call, color: AppColors.primary),
              title: const Text('Réunion standard',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('Jusqu\'à 25 participants',
                  style: TextStyle(color: Colors.white54)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const CreateMeetingScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups, color: AppColors.secondary),
              title: const Text('Grande conférence',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _isPro ? 'Jusqu\'à 1000 participants' : 'Passez Pro pour 1000+',
                style: TextStyle(
                    color: _isPro ? Colors.white54 : Colors.amber),
              ),
              onTap: () {
                Navigator.pop(context);
                if (_isPro) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CreateMeetingScreen(
                              largeConference: true)));
                } else {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProScreen()));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _joinMeeting() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const JoinMeetingScreen()));
  }

  void _showMeetingOptions(Map<String, dynamic> meeting) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.login, color: Colors.white),
              title: const Text('Rejoindre',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _enterMeeting(meeting['id'], meeting['title']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text('Partager',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                final joinUrl =
                    'https://crux-3c6be.web.app/join/${meeting['id']}';
                Share.share(
                    'Rejoins ma réunion CRUX : ${meeting['title']}\nID : ${meeting['id']}\nLien : $joinUrl');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('Quitter la réunion',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(context);
                _leaveMeeting(meeting['id']);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enterMeeting(String meetingId, String meetingName) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('meetings')
          .doc(meetingId)
          .get();
      if (!doc.exists) {
        if (mounted) {
          ElegantToast.show(context,
              title: 'Erreur',
              message: 'Réunion introuvable',
              type: ElegantToastType.error);
        }
        return;
      }

      final data = doc.data();
      final isLargeConference = data?['isLargeConference'] ?? false;
      final isOrganizer = data?['organizerId'] == widget.user.uid;

      if (isLargeConference) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LargeConferenceScreen(
              meetingId: meetingId,
              meetingName: meetingName,
              userId: widget.user.uid,
              userName: _displayName(),
              userEmail: widget.user.email,
              isHost: isOrganizer,
            ),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingScreen(
              meetingId: meetingId,
              meetingName: meetingName,
              userId: widget.user.uid,
              userName: _displayName(),
              userEmail: widget.user.email,
              isHost: isOrganizer,
            ),
          ),
        );
      }
    } catch (e) {
      crux.logger.e('Error entering meeting', error: e);
      if (mounted) {
        ElegantToast.show(context,
            title: 'Erreur',
            message: 'Impossible de rejoindre la réunion',
            type: ElegantToastType.error);
      }
    }
  }

  Future<void> _leaveMeeting(String meetingId) async {
    try {
      await FirebaseFirestore.instance
          .collection('meetings')
          .doc(meetingId)
          .update({
        'participants': FieldValue.arrayRemove([widget.user.uid]),
      });
      _loadMeetings();
      if (mounted) {
        ElegantToast.show(context,
            title: 'Succès',
            message: 'Vous avez quitté la réunion',
            type: ElegantToastType.success);
      }
    } catch (e) {
      crux.logger.e('Error leaving meeting', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.read<LocaleProvider>().locale.languageCode;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              floating: false,
              pinned: true,
              backgroundColor: AppColors.background,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  'CRUX',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withOpacity(0.3),
                        AppColors.background,
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                if (!_isPro)
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProScreen())),
                    icon: const Icon(Icons.star,
                        color: Colors.amber, size: 18),
                    label: Text('PRO',
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold)),
                  ),
                IconButton(
                  icon: const Icon(Icons.settings,
                      color: Colors.white70),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const SettingsScreen())),
                ),
                IconButton(
                  icon: const Icon(Icons.logout,
                      color: Colors.white70),
                  onPressed: () async {
                    await AuthService().signOut();
                    if (mounted)
                      Navigator.pushReplacementNamed(
                          context, '/');
                  },
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bonjour, ${_displayName()}',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.1),
                    const SizedBox(height: 8),
                    Text(
                      widget.user.email,
                      style: GoogleFonts.interTight(
                          color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.video_call,
                            title: 'Nouvelle réunion',
                            subtitle: 'Démarrer un appel',
                            color: AppColors.primary,
                            onTap: _showCreateMeetingDialog,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.login,
                            title: 'Rejoindre',
                            subtitle: 'Via un code',
                            color: AppColors.secondary,
                            onTap: _joinMeeting,
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 600.ms, delay: 200.ms),
                    const SizedBox(height: 32),
                    _buildStatsRow(),
                    const SizedBox(height: 32),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: AppColors.primary,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.white54,
                      labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
                      tabs: const [
                        Tab(text: 'RÉUNIONS ACTIVES'),
                        Tab(text: 'HISTORIQUE'),
                      ],
                    ),
                    SizedBox(
                      height: 400,
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildMeetingsList(),
                          _buildHistoryList(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _StatCard(
          value: _meetingCount.toString(),
          label: 'Réunions',
          icon: Icons.meeting_room,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: _formatDuration(_totalDuration),
          label: 'Temps total',
          icon: Icons.timer,
        ),
        const SizedBox(width: 12),
        _StatCard(
          value: _meetings.length.toString(),
          label: 'Actives',
          icon: Icons.circle,
          iconColor: Colors.green,
        ),
      ],
    ).animate().fadeIn(duration: 700.ms, delay: 400.ms);
  }

  Widget _buildMeetingsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_meetings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_call_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'Aucune réunion active',
              style: GoogleFonts.interTight(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Créez ou rejoignez une réunion',
              style: GoogleFonts.interTight(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _meetings.length,
      itemBuilder: (context, index) {
        final meeting = _meetings[index];
        return _MeetingCard(
          title: meeting['title'],
          organizer: meeting['organizer'],
          participantCount: meeting['participantCount'],
          onTap: () => _enterMeeting(meeting['id'], meeting['title']),
          onMore: () => _showMeetingOptions(meeting),
        ).animate().fadeIn(duration: 400.ms, delay: (index * 100).ms);
      },
    );
  }

  Widget _buildHistoryList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              'Aucun historique',
              style: GoogleFonts.interTight(color: Colors.white54, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Vos réunions passées apparaîtront ici',
              style: GoogleFonts.interTight(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final item = _history[index];
        final endedAt = item['endedAt'] != null
            ? (item['endedAt'] as Timestamp).toDate()
            : null;
        final dateStr = endedAt != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(endedAt)
            : 'Date inconnue';

        return _MeetingCard(
          title: item['title'],
          organizer: dateStr,
          participantCount: null,
          subtitle: 'Durée: ${_formatDuration(item['duration'] ?? 0)}',
          onTap: () {},
          onMore: () {},
        ).animate().fadeIn(duration: 400.ms, delay: (index * 100).ms);
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.interTight(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color? iconColor;

  const _StatCard({
    required this.value,
    required this.label,
    required this.icon,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor ?? Colors.white70, size: 20),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.interTight(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final String title;
  final String organizer;
  final int? participantCount;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  const _MeetingCard({
    required this.title,
    required this.organizer,
    this.participantCount,
    this.subtitle,
    required this.onTap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.video_call, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle ?? 'Organisateur: $organizer',
                    style: GoogleFonts.interTight(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  if (participantCount != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people, color: Colors.white38, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '$participantCount participant${participantCount == 1 ? '' : 's'}',
                          style: GoogleFonts.interTight(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}
