import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyArg6eFPp6trk50fCRGC_xqPgslkIa5WTE',
    appId: '1:33175700363:web:8dff2f40e10d1ead66658e',
    messagingSenderId: '33175700363',
    projectId: 'crux-3c6be',
    authDomain: 'crux-3c6be.firebaseapp.com',
    storageBucket: 'crux-3c6be.firebasestorage.app',
    measurementId: 'G-6GVHG2D4YB',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCvdzbDqAszGXUQ5iDesApht-Aps7_ObcQ',
    appId: '1:33175700363:android:47532d59f11f2e1a66658e',
    messagingSenderId: '33175700363',
    projectId: 'crux-3c6be',
    storageBucket: 'crux-3c6be.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyArg6eFPp6trk50fCRGC_xqPgslkIa5WTE',
    appId: '1:33175700363:ios:d1a2b3c4d5e6f7g8h9i0j',
    messagingSenderId: '33175700363',
    projectId: 'crux-3c6be',
    storageBucket: 'crux-3c6be.firebasestorage.app',
    iosBundleId: 'com.schac-crux.app',
  );
}
