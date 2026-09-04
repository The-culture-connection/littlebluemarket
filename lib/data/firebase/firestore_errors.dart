import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

import '../repositories/repositories.dart';

/// Turns a backend failure into one the app knows how to talk about.
///
/// This is the boundary the whole repository layer exists to draw: above it,
/// screens switch on the app's own exception types; below it, Firestore and the
/// commerce proxy have their own vocabularies. A `PERMISSION_DENIED` string
/// must never reach a person.
RepositoryException translateFirestoreError(Object error, [StackTrace? _]) {
  if (error is RepositoryException) return error;

  if (error is FirebaseFunctionsException) {
    return switch (error.code) {
      'unauthenticated' => const UnauthenticatedException(),
      'permission-denied' => PermissionException(
        error.message ?? 'Not allowed',
        cause: error,
      ),
      'not-found' => NotFoundException('record', error.details?.toString() ?? '?'),
      'invalid-argument' || 'failed-precondition' => ValidationException(
        error.message ?? 'That did not work',
        cause: error,
      ),
      'resource-exhausted' => RateLimitException(cause: error),
      'unavailable' || 'deadline-exceeded' => OfflineException(cause: error),
      _ => BackendException(
        error.message ?? 'Something went wrong',
        code: error.code,
        cause: error,
      ),
    };
  }

  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' => PermissionException(
        error.message ?? 'Not allowed',
        cause: error,
      ),
      'not-found' => NotFoundException('record', error.plugin),
      // Firestore reports an offline read this way when the cache misses.
      'unavailable' || 'network-request-failed' => OfflineException(cause: error),
      'resource-exhausted' => RateLimitException(cause: error),
      'unauthenticated' => const UnauthenticatedException(),
      _ => BackendException(
        error.message ?? 'Something went wrong',
        code: error.code,
        cause: error,
      ),
    };
  }

  return BackendException('$error', cause: error);
}

/// Runs [action], translating anything it throws.
Future<T> guardFirestore<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error, stack) {
    throw translateFirestoreError(error, stack);
  }
}

/// The stream equivalent, so a permission error on a live query surfaces as a
/// typed exception rather than a raw platform one.
extension GuardedStream<T> on Stream<T> {
  Stream<T> guarded() => handleError(
    (Object error, StackTrace stack) =>
        throw translateFirestoreError(error, stack),
  );
}
