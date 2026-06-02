import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDfVNAL2cV47g9WHPtXsaE8_4pWFpy3-Ls',
    appId: '1:667181830171:android:85399beb4fc1d087c4e8be',
    messagingSenderId: '667181830171',
    projectId: 'crux-8aa85',
    storageBucket: 'crux-8aa85.appspot.com',
  );

  // iOS: remplace ces valeurs depuis ta console Firebase
  // Console Firebase → Paramètres projet → Ajouter app iOS → Bundle ID: com.example.crux
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REMPLACE_PAR_IOS_API_KEY',
    appId: 'REMPLACE_PAR_IOS_APP_ID',
    messagingSenderId: '667181830171',
    projectId: 'crux-8aa85',
    storageBucket: 'crux-8aa85.appspot.com',
    iosBundleId: 'com.example.crux',
  );
}
