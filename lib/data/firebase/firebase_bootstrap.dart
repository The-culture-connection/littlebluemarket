import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../firebase_options.dart';

/// Brings Firebase up, once.
///
/// Called from `main` only when the app is built for the live backend, so a
/// fixture build neither needs configuration nor pays the start-up cost.
Future<void> initializeFirebase({bool useEmulators = false}) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (useEmulators) {
    // The emulator host differs on an Android emulator, which cannot see the
    // machine's localhost.
    const host = kIsWeb ? 'localhost' : '10.0.2.2';
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  }

  // Offline persistence is on by default on mobile, but the cache size is
  // worth being explicit about: this app reads the same catalog documents
  // repeatedly, and the default 100 MB is more than it will ever need.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: 40 * 1024 * 1024,
  );
}

/// Whether this build should point at local emulators.
const useFirebaseEmulators = bool.fromEnvironment('LBM_EMULATORS');

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

/// The only thing that talks to commerce.
///
/// Callable functions carry the Firebase ID token automatically, which is what
/// lets the proxy know who is asking without the app ever holding a storefront
/// credential.
final firebaseFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instance,
);
