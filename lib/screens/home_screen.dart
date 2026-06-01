import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../services/error_handler_service.dart';
import '../screens/meeting_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _meetingService = MeetingService();
  final _errorHandler = ErrorHandlerService();
  final _meetingNameController = TextEditingController();
  final _joinIdController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _meetingNameController.dispose();
    _joinIdController.dispose();
    super.dispose();
  }

  Future<void> _createMeeting() async {
    final name = _meetingNameController.text.trim();
    if (name.isEmpty) {
      _errorHandler.showErrorDialog(context, '⚠️ Attention', 'Entrez le nom de la réunion');
      return;
    }
    setState(() => _isCreating = true);
    try {
      final meetingId = await _meetingService.createMeeting(
        title: name,
        description: '',
        organizerName: widget.user.name,
        organizerId: widget.user.uid,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Délai dépassé. Vérifiez votre connexion Internet.'),
      );
      _meetingNameController.clear();
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => MeetingScreen(
          meetingId: meetingId,
          meetingName: name,
          userId: widget.user.uid,
          userName: widget.user.name,
          userEmail: widget.user.email,
          isHost: true,
        ),
      ));
    } catch (e) {
      if (mounted) _errorHandler.showErrorDialog(context, '❌ Erreur', e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _joinById(String id) async {
    if (id.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => MeetingScreen(
        meetingId: id,
        meetingName: 'Réunion',
        userId: widget.user.uid,
        userName: widget.user.name,
        userEmail: widget.user.email,
        isHost: false,
      ),
    ));
  }

  void _showJoinDialog() {
    _joinIdController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Rejoindre', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Entrez l\'ID de la réunion partagé par l\'hôte',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _joinIdController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'ID de la réunion',
                hintStyle: GoogleFonts.poppins(color: AppColors.textTertiary),
                prefixIcon: const Icon(Icons.tag, color: AppColors.secondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.secondary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Annuler', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final id = _joinIdController.text.trim();
              if (id.isEmpty) return;
              Navigator.pop(ctx);
              await _joinById(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Rejoindre', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Déconnexion', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        content: Text('Voulez-vous vraiment vous déconnecter ?', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _authService.signOut();
              if (mounted) Navigator.of(context).pushReplacementNamed('/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Déconnecter', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F3FF);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // App bar with gradient
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE74C3C), Color(0xFF8E44AD)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'CRUX',
                              style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 2,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.settings_outlined, color: Colors.white70),
                                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.logout, color: Colors.white70),
                                  onPressed: _logout,
                                ),
                              ],
                            ),
                          ],
                        ),
                        Text(
                          'Bonjour, ${widget.user.name.split(' ').first} 👋',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Prêt pour votre prochaine réunion ?',
                          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),

                  // Create meeting card
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE74C3C), Color(0xFF9B59B6), Color(0xFF8E44AD)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE74C3C).withOpacity(0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.video_call, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Nouvelle réunion',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // TextField with transparent fill so white text is visible
                        TextField(
                          controller: _meetingNameController,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Nom de la réunion...',
                            hintStyle: GoogleFonts.poppins(color: Colors.white54),
                            prefixIcon: const Icon(Icons.edit, color: Colors.white60, size: 20),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.15),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Colors.white, width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isCreating ? null : _createMeeting,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFFE74C3C),
                              disabledBackgroundColor: Colors.white60,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isCreating
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(color: Color(0xFFE74C3C), strokeWidth: 2.5),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.rocket_launch, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Démarrer la réunion',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Section title
                  Text(
                    'Actions rapides',
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Quick actions grid
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.group_add,
                          title: 'Rejoindre',
                          subtitle: 'Via un ID',
                          gradientColors: const [Color(0xFF8E44AD), Color(0xFF6C3483)],
                          onTap: _showJoinDialog,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.tune,
                          title: 'Paramètres',
                          subtitle: 'Préférences',
                          gradientColors: const [Color(0xFF3498DB), Color(0xFF2980B9)],
                          onTap: () => Navigator.pushNamed(context, '/settings'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.share,
                          title: 'Partager',
                          subtitle: 'Inviter',
                          gradientColors: const [Color(0xFF27AE60), Color(0xFF1E8449)],
                          onTap: () {
                            _errorHandler.showInfoSnackBar(context, '📱 Partagez l\'app CRUX avec vos contacts');
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.help_outline,
                          title: 'Aide',
                          subtitle: 'Support',
                          gradientColors: const [Color(0xFFF39C12), Color(0xFFD68910)],
                          onTap: () {
                            _errorHandler.showInfoSnackBar(context, '📧 support@crux.app');
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFEDE7F6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.secondary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.info_outline, color: AppColors.secondary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Les réunions s\'ouvrent dans votre navigateur via Jitsi Meet — gratuit et sécurisé.',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.grey.withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
