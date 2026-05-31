import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDfVNAL2cV47g9WHPtXsaE8_4pWFpy3-Ls',
    appId: '1:667181830171:android:85399beb4fc1d087c4e8be',
    messagingSenderId: '667181830171',
    projectId: 'crux-8aa85',
    storageBucket: 'crux-8aa85.appspot.com',
  );
}
