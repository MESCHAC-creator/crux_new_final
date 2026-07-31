String _displayName() {
  try {
    final fb = FirebaseAuth.instance.currentUser;
    if (fb?.displayName?.trim().isNotEmpty == true) return fb!.displayName!;
    if (fb?.email?.isNotEmpty == true && fb!.email!.contains('@')) return fb.email!.split('@')[0];
    return widget.user.name; // ✅ CORRIGÉ : user n'est pas nullable
  } catch (e) {
    crux.logger.e('_displayName error', error: e);
    return 'Utilisateur';
  }
}
final lang = context.read<LocaleProvider>().locale.languageCode; // ✅ EXPLICITE
