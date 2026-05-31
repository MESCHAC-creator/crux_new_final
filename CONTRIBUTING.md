# 🤝 Guide de Contribution

Merci de votre intérêt pour CRUX! Ce document vous guidera pour contribuer au projet.

## 🎯 Avant de commencer

1. Lisez [README.md](README.md)
2. Familiarisez-vous avec la structure du projet
3. Assurez-vous d'avoir les prérequis installés

## 📝 Code de Conduite

- Soyez respectueux
- Acceptez les critiques constructives
- Concentrez-vous sur ce qui est meilleur pour la communauté

## 🔄 Processus de Contribution

### 1. Fork & Clone
```bash
git clone https://github.com/yourusername/crux.git
cd crux
```

### 2. Créer une branche
```bash
git checkout -b feature/your-feature-name
```

### 3. Faire vos modifications
- Suivez le style de code existant
- Écrivez des commits clairs et concis
- Testez vos modifications

### 4. Format & Analyse
```bash
dart format lib/
flutter analyze
flutter test
```

### 5. Commit & Push
```bash
git add .
git commit -m "feat: description de votre modification"
git push origin feature/your-feature-name
```

### 6. Pull Request
- Décrivez clairement vos modifications
- Référencez les issues pertinentes
- Attendez la revue

## 📋 Guide de Style

### Dart
- Utilisez camelCase pour les variables
- Utilisez snake_case pour les fichiers
- Commentaires clairs et concis
- Maximum 100 caractères par ligne

### Commits
- `feat:` pour les nouvelles fonctionnalités
- `fix:` pour les corrections
- `docs:` pour la documentation
- `style:` pour le formatage
- `test:` pour les tests

## 🐛 Signaler un Bug

1. Vérifiez que le bug n'existe pas déjà
2. Créez une issue avec:
    - Description claire
    - Étapes pour reproduire
    - Comportement attendu
    - Version de Flutter/Dart

## 💡 Proposer une Fonctionnalité

1. Vérifiez que la fonctionnalité n'existe pas
2. Créez une issue décrivant:
    - Cas d'usage
    - Bénéfices
    - Implémentation possible

## ❓ Questions?

- Ouvrez une discussion sur GitHub
- Email: dev@crux.app

---

**Merci de contribuer à CRUX! 🚀**