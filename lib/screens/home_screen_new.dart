import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/premium_colors.dart';
import '../services/auth_service.dart';
import '../services/meeting_service.dart';
import '../models/user_model.dart';
import '../models/meeting_model.dart';
import '../widgets/premium_button.dart';
import 'meeting_screen_new.dart';

class HomeScreenNew extends StatefulWidget {
  final UserModel? user;

  const HomeScreenNew({Key? key, this.user}) : super(key: key);

  @override
  State<HomeScreenNew> createState() => _HomeScreenNewState();
}

class _HomeScreenNewState extends State<HomeScreenNew> {
  final AuthService _authService = AuthService();
  final MeetingService _meetingService = MeetingService();
  late TextEditingController _meetingNameController;
  late TextEditingController _meetingDescriptionController;
  List<MeetingModel> _recentMeetings = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _meetingNameController = TextEditingController();
    _meetingDescriptionController = TextEditingController();
    _loadMeetings();
  }

  @override
  void dispose() {
    _meetingNameController.dispose();
    _meetingDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadMeetings() async {
    setState(() => _isLoading = true);
    try {
      // TODO: Load from Firestore
      _recentMeetings = [];
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createMeeting() async {
    if (_meetingNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a meeting name')),
      );
      return;
    }

    try {
      final meetingId = await _meetingService.createMeeting(
        title: _meetingNameController.text,
        description: _meetingDescriptionController.text,
        organizerName: widget.user?.name ?? 'Host',
        organizerId: widget.user?.uid ?? '',
      );

      if (mounted) {
        Navigator.pop(context);
        final title = _meetingNameController.text;
        _meetingNameController.clear();
        _meetingDescriptionController.clear();

        // Navigate to meeting
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingScreenNew(
              meetingId: meetingId,
              meetingName: title,
              userId: widget.user?.uid ?? '',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _startInstantMeeting() async {
    final meetingId = DateTime.now().millisecondsSinceEpoch.toString();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingScreenNew(
          meetingId: meetingId,
          meetingName: 'Instant Meeting',
          userId: widget.user?.uid ?? '',
        ),
      ),
    );
  }

  void _showNewMeetingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: PremiumColors.snowWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Schedule a Meeting',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: PremiumColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _meetingNameController,
                decoration: InputDecoration(
                  labelText: 'Meeting Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: PremiumColors.icePrimary,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _meetingDescriptionController,
                minLines: 3,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: PremiumColors.icePrimary,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: PremiumButton(
                      label: 'Create',
                      isPrimary: true,
                      onPressed: _createMeeting,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PremiumColors.snowWhite,
      appBar: AppBar(
        backgroundColor: PremiumColors.snowWhite,
        elevation: 0,
        title: Text(
          'Welcome, ${widget.user?.name ?? 'User'}',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: PremiumColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: PremiumColors.icePrimary),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: PremiumColors.textSecondary),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: PremiumColors.errorRed),
            onPressed: () async {
              await _authService.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Quick actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: PremiumColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.videocam,
                          label: 'Start Instant Meeting',
                          color: PremiumColors.flamePrimary,
                          onPressed: _startInstantMeeting,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.calendar_today,
                          label: 'Schedule Meeting',
                          color: PremiumColors.icePrimary,
                          onPressed: _showNewMeetingDialog,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.link,
                          label: 'Join via Code',
                          color: PremiumColors.accentOrange,
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Join Code Feature Coming Soon')),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.phone,
                          label: 'Dial In',
                          color: PremiumColors.successGreen,
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Dial In Coming Soon')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Recent meetings
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Text(
                'Recent Meetings',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: PremiumColors.textPrimary,
                ),
              ),
            ),
          ),

          if (_isLoading)
            SliverToBoxAdapter(
              child: Center(
                child: CircularProgressIndicator(
                  color: PremiumColors.flamePrimary,
                ),
              ),
            )
          else if (_recentMeetings.isEmpty)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.videocam,
                        size: 64,
                        color: PremiumColors.textTertiary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No recent meetings',
                        style: GoogleFonts.poppins(
                          color: PremiumColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, index) {
                  final meeting = _recentMeetings[index];
                  return _MeetingCard(meeting: meeting);
                },
                childCount: _recentMeetings.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: PremiumColors.textPrimary,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  final MeetingModel meeting;

  const _MeetingCard({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Navigate to meeting
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PremiumColors.surfaceGray,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PremiumColors.borderGray),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meeting.title,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: PremiumColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            meeting.description,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: PremiumColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: PremiumColors.successGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        meeting.participants.length.toString(),
                        style: const TextStyle(
                          color: PremiumColors.successGreen,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
