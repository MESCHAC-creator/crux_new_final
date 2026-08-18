import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/colors.dart';
import '../utils/constants.dart';
import '../models/user_model.dart';
import '../models/meeting_model.dart';
import '../services/meeting_service.dart';
import '../services/auth_service.dart';
import '../widgets/custom_button.dart';
import '../screens/meeting_screen.dart';
import '../screens/login_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  const HomeScreen({super.key, required this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MeetingService _meetingService = MeetingService();
  final AuthService _authService = AuthService();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _customCodeController =
      TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController();
  bool _isCreating = false;
  bool _isJoining = false;
  bool _isScheduling = false;
  late TabController _tabController;
  List<MeetingModel> _scheduledMeetings = [];
  DateTime? _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadScheduledMeetings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _titleController.dispose();
    _customCodeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _loadScheduledMeetings() async {
    final meetings =
        await _meetingService.getScheduledMeetings(widget.user.uid);
    if (mounted) setState(() => _scheduledMeetings = meetings);
  }

  void _createMeeting() async {
    setState(() => _isCreating = true);
    try {
      final meeting = await _meetingService.createMeeting(
        'Reunion CRUX',
        widget.user.uid,
        widget.user.name,
      );
      if (meeting != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingScreen(
              meeting: meeting,
              user: widget.user,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de creer la reunion'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _joinMeeting() async {
    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entrez un code de reunion')),
      );
      return;
    }
    setState(() => _isJoining = true);
    try {
      final meeting = await _meetingService.joinMeeting(
        _codeController.text.trim().toUpperCase(),
      );
      if (meeting != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingScreen(
              meeting: meeting,
              user: widget.user,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reunion introuvable'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _scheduleMeeting() async {
    if (_titleController.text.trim().isEmpty ||
        _selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Remplissez le titre et choisissez une date')),
      );
      return;
    }
    setState(() => _isScheduling = true);
    try {
      final meeting = await _meetingService.scheduleMeeting(
        title: _titleController.text.trim(),
        hostId: widget.user.uid,
        hostName: widget.user.name,
        scheduledAt: _selectedDateTime!,
        customCode: _customCodeController.text.trim().isEmpty
            ? null
            : _customCodeController.text.trim(),
        description: _descriptionController.text.trim(),
      );
      if (meeting != null && mounted) {
        _titleController.clear();
        _customCodeController.clear();
        _descriptionController.clear();
        setState(() => _selectedDateTime = null);
        _loadScheduledMeetings();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reunion programmee ! Code: ${meeting.id}'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Code deja utilise ou erreur'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScheduling = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(hours: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark(),
        child: child!,
      ),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark(),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _logout() async {
    await _authService.logout();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _startScheduledMeeting(MeetingModel meeting) async {
    await _meetingService.activateMeeting(meeting.id);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MeetingScreen(
            meeting: meeting,
            user: widget.user,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'CRUX',
          style: TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
            fontSize: 20,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.grey,
          tabs: const [
            Tab(text: 'Accueil'),
            Tab(text: 'Programmes'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHomeTab(),
          _buildScheduledTab(),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Bonjour, ${widget.user.name} !',
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Que voulez-vous faire ?',
            style: TextStyle(color: AppColors.grey, fontSize: 14),
          ),
          const SizedBox(height: 32),
          // Nouvelle reunion
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.video_call,
                        color: AppColors.primary, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Nouvelle reunion',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Demarrez une reunion instantanee',
                  style: TextStyle(
                      color: AppColors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                CustomButton(
                  text: AppConstants.newMeeting,
                  onPressed: _createMeeting,
                  isLoading: _isCreating,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Rejoindre reunion
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.group_add,
                        color: AppColors.primary, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Rejoindre une reunion',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entrez le code de la reunion',
                  style: TextStyle(
                      color: AppColors.grey, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  style: const TextStyle(
                    color: AppColors.white,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: AppConstants.meetingCode,
                    hintStyle:
                        const TextStyle(color: AppColors.grey),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.tag,
                        color: AppColors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                CustomButton(
                  text: AppConstants.joinMeeting,
                  onPressed: _joinMeeting,
                  isLoading: _isJoining,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Programmer reunion
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.calendar_today,
                        color: AppColors.primary, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Programmer une reunion',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Titre de la reunion',
                    hintStyle:
                        const TextStyle(color: AppColors.grey),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.title,
                        color: AppColors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descriptionController,
                  style: const TextStyle(color: AppColors.white),
                  decoration: InputDecoration(
                    hintText: 'Description (optionnel)',
                    hintStyle:
                        const TextStyle(color: AppColors.grey),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.description,
                        color: AppColors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customCodeController,
                  style: const TextStyle(color: AppColors.white),
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'Code personnalise (optionnel)',
                    hintStyle:
                        const TextStyle(color: AppColors.grey),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.tag,
                        color: AppColors.grey),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickDateTime,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time,
                            color: AppColors.grey),
                        const SizedBox(width: 12),
                        Text(
                          _selectedDateTime == null
                              ? 'Choisir date et heure'
                              : DateFormat('dd/MM/yyyy HH:mm')
                                  .format(_selectedDateTime!),
                          style: TextStyle(
                            color: _selectedDateTime == null
                                ? AppColors.grey
                                : AppColors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                CustomButton(
                  text: 'Programmer',
                  onPressed: _scheduleMeeting,
                  isLoading: _isScheduling,
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildScheduledTab() {
    if (_scheduledMeetings.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today,
                color: AppColors.grey, size: 60),
            const SizedBox(height: 16),
            const Text(
              'Aucune reunion programmee',
              style: TextStyle(color: AppColors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Programmez une reunion depuis l\'onglet Accueil',
              style:
                  TextStyle(color: AppColors.grey, fontSize: 12),
            ),
            const SizedBox(height: 32),
            CustomButton(
              text: 'Programmer maintenant',
              onPressed: () => _tabController.animateTo(0),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _scheduledMeetings.length,
      itemBuilder: (context, index) {
        final meeting = _scheduledMeetings[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      meeting.title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      meeting.id,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
              if (meeting.description != null &&
                  meeting.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meeting.description!,
                  style: const TextStyle(
                      color: AppColors.grey, fontSize: 13),
                ),
              ],
              if (meeting.scheduledAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        color: AppColors.grey, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('dd/MM/yyyy HH:mm')
                          .format(meeting.scheduledAt!),
                      style: const TextStyle(
                          color: AppColors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              CustomButton(
                text: 'Demarrer la reunion',
                onPressed: () =>
                    _startScheduledMeeting(meeting),
              ),
            ],
          ),
        );
      },
    );
  }
}
