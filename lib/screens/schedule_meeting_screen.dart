import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/scheduled_meeting_model.dart';
import '../theme/colors.dart';
import '../services/meeting_service.dart';
import '../utils/logger.dart' as crux;
import '../widgets/custom_button.dart';
import '../widgets/elegant_toast.dart';

/// **ScheduleMeetingScreen** — Écran professionnel de planification de réunions.
/// Inspire par Zoom, Google Meet et Teams. Complète la roadmap Phase 2-3.
class ScheduleMeetingScreen extends StatefulWidget {
  const ScheduleMeetingScreen({super.key});

  @override
  State<ScheduleMeetingScreen> createState() => _ScheduleMeetingScreenState();
}

class _ScheduleMeetingScreenState extends State<ScheduleMeetingScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _passcodeCtrl = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _timezone = 'UTC';
  String _meetingType = 'standard'; // standard, largeConference

  bool _waitingRoom = false;
  bool _allowBeforeHost = false;
  bool _disableGuests = false;
  bool _cameraEnabled = true;
  bool _micEnabled = true;
  bool _screenShareEnabled = true;
  bool _chatEnabled = true;
  bool _recordAutomatically = false;

  bool _notifyOneHour = true;
  bool _notifyFifteenMin = true;
  bool _notifyFiveMin = true;
  bool _notifyAtStart = true;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _passcodeCtrl.dispose();
    super.dispose();
  }

  String _displayName() {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb?.displayName?.trim().isNotEmpty == true) return fb!.displayName!;
    if (fb?.email?.isNotEmpty == true && fb!.email!.contains('@')) {
      return fb.email!.split('@')[0];
    }
    return 'Utilisateur';
  }

  String _userEmail() {
    return FirebaseAuth.instance.currentUser?.email ?? 'unknown@crux.app';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ),
            dialogBackgroundColor: AppColors.surface,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surface,
            ),
            dialogBackgroundColor: AppColors.surface,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _scheduleMeeting() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Donne un titre à ta réunion');
      return;
    }

    if (_selectedDate == null) {
      setState(() => _error = 'Sélectionne une date');
      return;
    }

    if (_selectedTime == null) {
      setState(() => _error = 'Sélectionne une heure');
      return;
    }

    final passcode = _passcodeCtrl.text.trim();
    if (passcode.isNotEmpty && (passcode.length < 4 || passcode.length > 6)) {
      setState(() => _error = 'Le code d\'accès doit faire 4 à 6 chiffres');
      return;
    }
    if (passcode.isNotEmpty && !RegExp(r'^\d+$').hasMatch(passcode)) {
      setState(() => _error = 'Le code d\'accès ne doit contenir que des chiffres');
      return;
    }

    // Construire l'heure de début
    final startTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final endTime = startTime.add(const Duration(hours: 1));

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = MeetingService();
      final meeting = await service.scheduleProMeeting(
        title: title,
        description: _descriptionCtrl.text.trim(),
        organizerName: _displayName(),
        organizerEmail: _userEmail(),
        startTime: startTime,
        endTime: endTime,
        timezone: _timezone,
        passcode: passcode.isNotEmpty ? passcode : null,
        waitingRoomEnabled: _waitingRoom,
        allowBeforeHost: _allowBeforeHost,
        disableGuests: _disableGuests,
        cameraEnabled: _cameraEnabled,
        microphoneEnabled: _micEnabled,
        screenShareEnabled: _screenShareEnabled,
        chatEnabled: _chatEnabled,
        recordAutomatically: _recordAutomatically,
        notifyAtOneHour: _notifyOneHour,
        notifyAtFifteenMin: _notifyFifteenMin,
        notifyAtFiveMin: _notifyFiveMin,
        notifyAtStart: _notifyAtStart,
        meetingType: _meetingType == 'largeConference'
            ? MeetingType.largeConference
            : MeetingType.standard,
        isLargeConference: _meetingType == 'largeConference',
      );

      if (!mounted) return;

      ElegantToast.show(
        context,
        title: 'Réunion planifiée',
        message: 'Réunion créée le ${DateFormat('dd/MM/yyyy HH:mm').format(startTime)}',
        type: ElegantToastType.success,
      );

      Navigator.pop(context, meeting);
    } catch (e) {
      crux.logger.e('ScheduleMeetingScreen._scheduleMeeting error', error: e);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Erreur lors de la planification. Réessaie.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = _selectedDate != null
        ? DateFormat('dd MMM yyyy', 'fr_FR').format(_selectedDate!)
        : 'Sélectionner une date';

    final timeStr = _selectedTime != null
        ? _selectedTime!.format(context)
        : 'Sélectionner l\'heure';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Planifier une réunion',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icône d'en-tête ──────────────────────────────────────────
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 24),

              // ── SECTION 1 : INFORMATIONS DE BASE ─────────────────────────
              _buildSectionTitle('Informations de base'),
              const SizedBox(height: 12),

              _buildTextfield(
                controller: _titleCtrl,
                label: 'Titre de la réunion',
                hint: 'Ex. Sprint Planning Équipe Tech',
              ),
              const SizedBox(height: 12),

              _buildTextfield(
                controller: _descriptionCtrl,
                label: 'Description (optionnel)',
                hint: 'Décris le sujet de la réunion',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // ── SECTION 2 : DATE & HEURE ────────────────────────────────
              _buildSectionTitle('Date et heure'),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildTapField(
                      icon: Icons.calendar_today_rounded,
                      label: dateStr,
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTapField(
                      icon: Icons.access_time_rounded,
                      label: timeStr,
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildDropdown(
                label: 'Fuseau horaire',
                value: _timezone,
                items: [
                  'UTC',
                  'Europe/Paris',
                  'Europe/London',
                  'America/New_York',
                  'America/Los_Angeles',
                  'Asia/Tokyo',
                  'Australia/Sydney',
                ],
                onChanged: (v) => setState(() => _timezone = v),
              ),
              const SizedBox(height: 20),

              // ── SECTION 3 : SÉCURITÉ ────────────────────────────────────
              _buildSectionTitle('Sécurité'),
              const SizedBox(height: 12),

              _buildToggleTile(
                icon: Icons.lock_rounded,
                title: 'Salle d\'attente',
                subtitle: 'Approuver les participants avant l\'entrée',
                value: _waitingRoom,
                onChanged: (v) => setState(() => _waitingRoom = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.person_add_disabled_rounded,
                title: 'Autoriser avant l\'hôte',
                subtitle: 'Les participants peuvent rejoindre avant vous',
                value: _allowBeforeHost,
                onChanged: (v) => setState(() => _allowBeforeHost = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.people_outline_rounded,
                title: 'Désactiver les invités',
                subtitle: 'Seulement les utilisateurs authentifiés peuvent accéder',
                value: _disableGuests,
                onChanged: (v) => setState(() => _disableGuests = v),
              ),
              const SizedBox(height: 12),

              _buildTextfield(
                controller: _passcodeCtrl,
                label: 'Code d\'accès (optionnel)',
                hint: '4-6 chiffres',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),

              // ── SECTION 4 : AUDIO / VIDÉO ────────────────────────────────
              _buildSectionTitle('Paramètres audio/vidéo'),
              const SizedBox(height: 12),

              _buildToggleTile(
                icon: Icons.videocam_rounded,
                title: 'Caméra activée',
                value: _cameraEnabled,
                onChanged: (v) => setState(() => _cameraEnabled = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.mic_rounded,
                title: 'Micro activé',
                value: _micEnabled,
                onChanged: (v) => setState(() => _micEnabled = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.screen_share_rounded,
                title: 'Partage d\'écran autorisé',
                value: _screenShareEnabled,
                onChanged: (v) => setState(() => _screenShareEnabled = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Chat activé',
                value: _chatEnabled,
                onChanged: (v) => setState(() => _chatEnabled = v),
              ),
              const SizedBox(height: 20),

              // ── SECTION 5 : NOTIFICATIONS ────────────────────────────────
              _buildSectionTitle('Notifications'),
              const SizedBox(height: 12),

              _buildToggleTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notification 1 heure avant',
                value: _notifyOneHour,
                onChanged: (v) => setState(() => _notifyOneHour = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notification 15 min avant',
                value: _notifyFifteenMin,
                onChanged: (v) => setState(() => _notifyFifteenMin = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notification 5 min avant',
                value: _notifyFiveMin,
                onChanged: (v) => setState(() => _notifyFiveMin = v),
              ),
              const SizedBox(height: 10),

              _buildToggleTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notification au démarrage',
                value: _notifyAtStart,
                onChanged: (v) => setState(() => _notifyAtStart = v),
              ),
              const SizedBox(height: 20),

              // ── SECTION 6 : ENREGISTREMENT ────────────────────────────────
              _buildSectionTitle('Enregistrement'),
              const SizedBox(height: 12),

              _buildToggleTile(
                icon: Icons.record_voice_over_rounded,
                title: 'Enregistrement automatique',
                subtitle: 'Enregistrer la réunion dans le cloud',
                value: _recordAutomatically,
                onChanged: (v) => setState(() => _recordAutomatically = v),
              ),
              const SizedBox(height: 20),

              // ── MESSAGE D'ERREUR ─────────────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_rounded, color: AppColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.spaceGrotesk(
                            color: AppColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),

              // ── BOUTONS ──────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      label: 'Annuler',
                      backgroundColor: AppColors.surfaceVariant,
                      textColor: AppColors.textPrimary,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      label: _loading ? 'Planification…' : 'Planifier',
                      isLoading: _loading,
                      onPressed: _loading ? () {} : _scheduleMeeting,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildTextfield({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: GoogleFonts.spaceGrotesk(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.spaceGrotesk(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
            filled: true,
            fillColor: AppColors.surfaceVariant,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTapField({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppColors.surface,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: value ? AppColors.primary.withOpacity(0.15) : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: value ? AppColors.primary : AppColors.textTertiary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
              inactiveTrackColor: AppColors.border,
            ),
          ],
        ),
      ),
    );
  }
}
