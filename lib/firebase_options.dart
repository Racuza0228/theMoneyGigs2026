// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
            'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
              'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
              'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
              'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ANDROID CONFIGURATION
  // Get these values from google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAaeUyThBtTn3mDT8mcGOP40Ijpk1Ay_H8',           // From "api_key" -> "current_key"
    appId: '1:759371429570:android:bbd3987121d4ed1b906d5b',             // From "client" -> "mobilesdk_app_id"
    messagingSenderId: '759371429570"',      // From "project_number"
    projectId: 'moneygigs-cf2c5',              // From "project_id"
    storageBucket: 'moneygigs-cf2c5.firebasestorage.app',     // From "storage_bucket"
  );

  // IOS CONFIGURATION
  // Get these values from GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDGOOP9LMEafCMaCa2EKKeAJeuWlwIQ-kM',               // From API_KEY
    appId: '1:759371429570:ios:335da0f5618697d2906d5b',                 // From GOOGLE_APP_ID
    messagingSenderId: '759371429570',      // From GCM_SENDER_ID
    projectId: 'moneygigs-cf2c5',              // From PROJECT_ID
    storageBucket: 'moneygigs-cf2c5.firebasestorage.app',     // From STORAGE_BUCKET
    iosBundleId: 'com.themoneygigs.moneygigs',            // From BUNDLE_ID
  );
}