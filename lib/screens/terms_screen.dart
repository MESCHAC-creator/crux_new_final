import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/colors.dart';
import '../l10n/app_translations.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final lang = context.watch<LocaleProvider>().locale.languageCode;
    final bgColor = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF5F3FF);
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    final title = AppTranslations.t('terms_of_use', lang);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE74C3C), Color(0xFF8E44AD)],
            ),
          ),
        ),
        title: Text(
          title,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(isDark: isDark, icon: Icons.gavel, title: title),
            const SizedBox(height: 20),
            _Section(
              cardColor: cardColor,
              textColor: textColor,
              title: _t(lang, 'Acceptation des conditions', 'Acceptance of Terms', 'Aceptación de términos', 'Annahme der Bedingungen'),
              body: _t(lang,
                'En utilisant CRUX, vous acceptez ces conditions d\'utilisation dans leur intégralité. Si vous n\'acceptez pas ces conditions, veuillez ne pas utiliser l\'application.',
                'By using CRUX, you agree to these terms of use in their entirety. If you do not agree to these terms, please do not use the application.',
                'Al utilizar CRUX, acepta estos términos de uso en su totalidad. Si no acepta estos términos, por favor no utilice la aplicación.',
                'Durch die Nutzung von CRUX stimmen Sie diesen Nutzungsbedingungen in ihrer Gesamtheit zu. Wenn Sie diesen Bedingungen nicht zustimmen, verwenden Sie die Anwendung bitte nicht.',
              ),
            ),
            _Section(
              cardColor: cardColor,
              textColor: textColor,
              title: _t(lang, 'Utilisation acceptable', 'Acceptable Use', 'Uso aceptable', 'Akzeptable Nutzung'),
              body: _t(lang,
                'Vous vous engagez à utiliser CRUX uniquement à des fins légales et conformément aux présentes conditions. Il est interdit de :\n• Utiliser CRUX pour des activités illégales\n• Harceler ou menacer d\'autres utilisateurs\n• Partager du contenu offensant ou illicite\n• Tenter de compromettre la sécurité du service',
                'You agree to use CRUX only for lawful purposes and in accordance with these terms. It is prohibited to:\n• Use CRUX for illegal activities\n• Harass or threaten other users\n• Share offensive or unlawful content\n• Attempt to compromise the security of the service',
                'Usted se compromete a utilizar CRUX únicamente con fines legales y de acuerdo con estos términos. Está prohibido:\n• Usar CRUX para actividades ilegales\n• Acosar o amenazar a otros usuarios\n• Compartir contenido ofensivo o ilícito\n• Intentar comprometer la seguridad del servicio',
                'Sie verpflichten sich, CRUX nur für rechtmäßige Zwecke und gemäß diesen Bedingungen zu nutzen. Es ist verboten:\n• CRUX für illegale Aktivitäten zu nutzen\n• Andere Benutzer zu belästigen oder zu bedrohen\n• Beleidigende oder rechtswidrige Inhalte zu teilen\n• Versuchen, die Sicherheit des Dienstes zu gefährden',
              ),
            ),
            _Section(
              cardColor: cardColor,
              textColor: textColor,
              title: _t(lang, 'Propriété intellectuelle', 'Intellectual Property', 'Propiedad intelectual', 'Geistiges Eigentum'),
              body: _t(lang,
                'CRUX et tous ses contenus (logo, interface, code) sont protégés par les lois sur la propriété intellectuelle. Toute reproduction ou distribution sans autorisation est strictement interdite.',
                'CRUX and all its content (logo, interface, code) are protected by intellectual property laws. Any reproduction or distribution without authorization is strictly prohibited.',
                'CRUX y todo su contenido (logotipo, interfaz, código) están protegidos por las leyes de propiedad intelectual. Cualquier reproducción o distribución sin autorización está estrictamente prohibida.',
                'CRUX und alle seine Inhalte (Logo, Benutzeroberfläche, Code) sind durch Gesetze zum Schutz des geistigen Eigentums geschützt. Jede Vervielfältigung oder Verbreitung ohne Genehmigung ist strengstens untersagt.',
              ),
            ),
            _Section(
              cardColor: cardColor,
              textColor: textColor,
              title: _t(lang, 'Responsabilité', 'Liability', 'Responsabilidad', 'Haftung'),
              body: _t(lang,
                'CRUX est fourni "tel quel" sans garantie d\'aucune sorte. Nous ne sommes pas responsables des interruptions de service, pertes de données ou dommages indirects résultant de l\'utilisation de l\'application.',
                'CRUX is provided "as is" without warranty of any kind. We are not responsible for service interruptions, data loss, or indirect damages resulting from the use of the application.',
                'CRUX se proporciona "tal cual" sin garantía de ningún tipo. No somos responsables de interrupciones del servicio, pérdida de datos o daños indirectos resultantes del uso de la aplicación.',
                'CRUX wird "wie besehen" ohne jegliche Gewährleistung bereitgestellt. Wir haften nicht für Dienstunterbrechungen, Datenverluste oder indirekte Schäden, die aus der Nutzung der Anwendung resultieren.',
              ),
            ),
            _Section(
              cardColor: cardColor,
              textColor: textColor,
              title: _t(lang, 'Modifications', 'Modifications', 'Modificaciones', 'Änderungen'),
              body: _t(lang,
                'Nous nous réservons le droit de modifier ces conditions à tout moment. Les modifications entrent en vigueur dès leur publication dans l\'application. L\'utilisation continue de CRUX après modification vaut acceptation des nouvelles conditions.',
                'We reserve the right to modify these terms at any time. Modifications take effect upon publication in the application. Continued use of CRUX after modification constitutes acceptance of the new terms.',
                'Nos reservamos el derecho de modificar estos términos en cualquier momento. Las modificaciones entran en vigor al momento de su publicación en la aplicación. El uso continuado de CRUX después de la modificación constituye la aceptación de los nuevos términos.',
                'Wir behalten uns das Recht vor, diese Bedingungen jederzeit zu ändern. Änderungen treten mit ihrer Veröffentlichung in der Anwendung in Kraft. Die weitere Nutzung von CRUX nach einer Änderung gilt als Annahme der neuen Bedingungen.',
              ),
            ),
            _Section(
              cardColor: cardColor,
              textColor: textColor,
              title: _t(lang, 'Contact', 'Contact', 'Contacto', 'Kontakt'),
              body: _t(lang,
                'Pour toute question relative à ces conditions, contactez-nous à :\nkouakouchristevann@gmail.com',
                'For any questions regarding these terms, contact us at:\nkouakouchristevann@gmail.com',
                'Para cualquier pregunta relacionada con estos términos, contáctenos en:\nkouakouchristevann@gmail.com',
                'Bei Fragen zu diesen Bedingungen kontaktieren Sie uns unter:\nkouakouchristevann@gmail.com',
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _t(lang, 'Dernière mise à jour : Juin 2026', 'Last updated: June 2026', 'Última actualización: Junio 2026', 'Zuletzt aktualisiert: Juni 2026'),
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _t(String lang, String fr, String en, String es, String de) {
    switch (lang) {
      case 'en': return en;
      case 'es': return es;
      case 'de': return de;
      default: return fr;
    }
  }
}

class _Header extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  const _Header({required this.isDark, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFE74C3C), Color(0xFF8E44AD)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final Color cardColor;
  final Color textColor;
  final String title;
  final String body;
  const _Section({required this.cardColor, required this.textColor, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 10),
          Text(body, style: GoogleFonts.poppins(fontSize: 13, color: textColor, height: 1.6)),
        ],
      ),
    );
  }
}
