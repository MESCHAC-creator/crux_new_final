import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/colors.dart';
import '../services/pro_service.dart';
import '../utils/logger.dart';
import '../widgets/elegant_toast.dart';
import '../widgets/custom_button.dart';

/// Écran de présentation et de souscription à CRUX PRO.
/// Appelé depuis HomeScreen : `ProScreen()`.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  bool _loading = false;

  static const _features = [
    ('Jusqu\'à 1000 participants', Icons.groups),
    ('Réunions sans limite de durée', Icons.all_inclusive),
    ('Enregistrement des réunions', Icons.fiber_manual_record),
    ('Support prioritaire', Icons.support_agent),
  ];

  Future<void> _subscribe() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      if (mounted) {
        ElegantToast.show(
          context,
          title: 'Erreur',
          message: 'Session expirée, reconnecte-toi',
          type: ElegantToastType.error,
        );
      }
      return;
    }

    setState(() => _loading = true);
    try {
      await ProService().startPayment(
        userId: current.uid,
        userName: current.displayName ?? current.email ?? 'Utilisateur',
        userEmail: current.email,
      );
    } catch (e) {
      logger.e('ProScreen._subscribe error', error: e);
      if (mounted) {
        ElegantToast.show(
          context,
          title: 'Erreur',
          message: 'Impossible d\'ouvrir la page de paiement',
          type: ElegantToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = ProService().priceXof;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'CRUX PRO',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.star, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 24),
              Text(
                'Passe à CRUX PRO',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Débloque les grandes conférences et bien plus.',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ..._features.map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Icon(f.$2, color: AppColors.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          f.$1,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$price FCFA / mois',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Icon(Icons.workspace_premium, color: Colors.amber),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              CustomButton(
                label: _loading ? 'Ouverture…' : 'Souscrire maintenant',
                isLoading: _loading,
                onPressed: _loading ? () {} : _subscribe,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Paiement sécurisé via PayDunya',
                  style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
