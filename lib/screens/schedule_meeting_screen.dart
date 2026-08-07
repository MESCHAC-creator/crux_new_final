// lib/screens/schedule_meeting_screen.dart
//
// Écran de planification réécrit (style « Obsidian Mono »).
//
// CORRECTIFS apportés par rapport à la version d'origine :
//   1. Écrit via [ScheduleService] → collection `meetings` (celle que
//      l'accueil lit) + miroir `scheduled_meetings`, dates en Timestamp.
//   2. Sélecteur de DURÉE (absent avant : `scheduledEnd` valait toujours
//      start + 1h en dur).
//   3. Interdit un horaire dans le passé, avec message clair (avant : on
//      pouvait planifier hier, la réunion n'apparaissait jamais).
//   4. Anti double-tap (`_submitting` + verrou statique du service) : plus de
//      réunions dupliquées.
//   5. Programme réellement les rappels locaux et l'affiche dans le résumé.
//   6. Toute erreur est remontée à l'utilisateur (avant : `catch (e) {}` muet).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/meeting_model.dart';
import '../services/schedule_service.dart';
import '../theme/colors.dart';
import '../utils/logger.dart' as crux;

class ScheduleMeetingScreen extends StatefulWidget {
  const ScheduleMeetingScreen({super.key, this.initialStart});

  /// Créneau pré-rempli (depuis un calendrier ou un raccourci).
  final DateTime? initialStart;

  @override
  State<ScheduleMeetingScreen> createState() => _ScheduleMeetingScreenState();
}

class _ScheduleMeetingScreenState extends State<ScheduleMeetingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _service = ScheduleService();

  late DateTime _start;
  Duration _duration = const Duration(minutes: 45);

  bool _usePasscode = false;
  bool _waitingRoom = false;
  bool _largeConference = false;
  bool _remind1h = true;
  bool _remind15 = true;
  bool _remind5 = false;
  bool _remindStart = true;
  bool _submitting = false;

  static const _durations = <Duration>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(hours: 1),
    Duration(hours: 2),
    Duration(hours: 4),
  ];

  @override
  void initState() {
    super.initState();
    final base = widget.initialStart ??
        DateTime.now().add(const Duration(minutes: 30));
    // Arrondi au quart d'heure supérieur.
    final rounded = DateTime(
      base.year,
      base.month,
      base.day,
      base.hour,
      (base.minute / 15).ceil() * 15,
    );
    _start = rounded;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ pickers

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.textOnPrimary,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _start.hour,
        _start.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: AppColors.textOnPrimary,
            surface: AppColors.surface,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  // ------------------------------------------------------------------- submit

  Future<void> _submit() async {
    if (_submitting || ScheduleService.isBusy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    try {
      final result = await _service.scheduleMeeting(
        title: _titleCtrl.text,
        description: _descCtrl.text,
        startTime: _start,
        duration: _duration,
        passcode: _usePasscode ? _passCtrl.text.trim() : null,
        waitingRoomEnabled: _waitingRoom,
        isLargeConference: _largeConference,
        notifyAtOneHour: _remind1h,
        notifyAtFifteenMin: _remind15,
        notifyAtFiveMin: _remind5,
        notifyAtStart: _remindStart,
      );
      if (!mounted) return;
      await _showSuccessSheet(result);
      if (mounted) Navigator.of(context).pop(result.meeting);
    } on ScheduleException catch (e) {
      if (!mounted) return;
      _snack(e.message, isError: true);
    } catch (e, st) {
      crux.logger.e('ScheduleMeetingScreen._submit', error: e, stackTrace: st);
      if (!mounted) return;
      _snack('Impossible de planifier la réunion.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          backgroundColor:
              isError ? AppColors.errorSurface : AppColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isError ? AppColors.error : AppColors.border,
            ),
          ),
        ),
      );
  }

  Future<void> _showSuccessSheet(ScheduleResult result) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.event_available_rounded,
                color: AppColors.primary, size: 36),
            const SizedBox(height: 14),
            Text(
              'Réunion planifiée',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatFullDate(result.meeting.startTime)} · '
              '${_formatDuration(result.meeting.duration)}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      result.shareLink,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copier le lien',
                    icon: const Icon(Icons.copy_rounded,
                        color: AppColors.primary, size: 20),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.shareLink));
                      _snack('Lien copié');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              result.remindersScheduled > 0
                  ? '${result.remindersScheduled} rappel(s) programmé(s) sur cet appareil.'
                  : 'Aucun rappel programmé (échéance trop proche).',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Terminé',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Planifier une réunion',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                _field(
                  controller: _titleCtrl,
                  label: 'Titre',
                  hint: 'Point hebdo équipe produit',
                  maxLength: 120,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Le titre est obligatoire'
                      : null,
                ),
                const SizedBox(height: 16),
                _field(
                  controller: _descCtrl,
                  label: 'Description (optionnel)',
                  hint: 'Ordre du jour, liens utiles…',
                  maxLines: 3,
                  maxLength: 500,
                ),
                const SizedBox(height: 24),
                _sectionTitle('Quand'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _pickerTile(
                        icon: Icons.calendar_today_rounded,
                        label: 'Date',
                        value: _formatDate(_start),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _pickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'Heure',
                        value: _formatTime(_start),
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                if (_start.isBefore(DateTime.now()))
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: const [
                        Icon(Icons.error_outline_rounded,
                            color: AppColors.warning, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cet horaire est déjà passé.',
                            style: TextStyle(
                                color: AppColors.warning, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                _sectionTitle('Durée'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _durations
                      .map((d) => _chip(
                            label: _formatDuration(d),
                            selected: d == _duration,
                            onTap: () => setState(() => _duration = d),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fin prévue à ${_formatTime(_start.add(_duration))}',
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 12),
                ),
                const SizedBox(height: 26),
                _sectionTitle('Rappels'),
                const SizedBox(height: 6),
                _switchTile(
                  '1 heure avant',
                  _remind1h,
                  (v) => setState(() => _remind1h = v),
                ),
                _switchTile(
                  '15 minutes avant',
                  _remind15,
                  (v) => setState(() => _remind15 = v),
                ),
                _switchTile(
                  '5 minutes avant',
                  _remind5,
                  (v) => setState(() => _remind5 = v),
                ),
                _switchTile(
                  'Au démarrage',
                  _remindStart,
                  (v) => setState(() => _remindStart = v),
                ),
                const SizedBox(height: 26),
                _sectionTitle('Sécurité & format'),
                const SizedBox(height: 6),
                _switchTile(
                  'Code d\'accès',
                  _usePasscode,
                  (v) => setState(() => _usePasscode = v),
                  subtitle: '4 à 6 chiffres demandés à l\'entrée',
                ),
                if (_usePasscode)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: _field(
                      controller: _passCtrl,
                      label: 'Code',
                      hint: '1234',
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (v) {
                        if (!_usePasscode) return null;
                        final value = v?.trim() ?? '';
                        if (!RegExp(r'^\d{4,6}$').hasMatch(value)) {
                          return 'Entre 4 et 6 chiffres';
                        }
                        return null;
                      },
                    ),
                  ),
                _switchTile(
                  'Salle d\'attente',
                  _waitingRoom,
                  (v) => setState(() => _waitingRoom = v),
                  subtitle: 'L\'hôte admet chaque participant',
                ),
                _switchTile(
                  'Grande conférence',
                  _largeConference,
                  (v) => setState(() => _largeConference = v),
                  subtitle: 'Au-delà de 6 participants (mode SFU)',
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              disabledBackgroundColor: AppColors.surfaceElevated,
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            // Bouton désactivé pendant l'envoi → protège du double tap.
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.textSecondary,
                    ),
                  )
                : const Text(
                    'Planifier la réunion',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        hintStyle:
            const TextStyle(color: AppColors.textDisabled, fontSize: 14),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.borderFocused),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        color: AppColors.textTertiary, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textOnPrimary : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _switchTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.textOnPrimary,
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceVariant,
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                style: const TextStyle(
                    color: AppColors.textTertiary, fontSize: 12),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------- formats

  static const _months = [
    'jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
  ];
  static const _days = [
    'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.',
  ];

  String _formatDate(DateTime d) =>
      '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _formatFullDate(DateTime d) => '${_formatDate(d)} à ${_formatTime(d)}';

  String _formatDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h} h' : '${h} h ${m}';
  }
}
