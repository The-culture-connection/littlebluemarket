/// Failures the app knows how to talk about.
///
/// Repositories translate whatever their backend threw — a Firestore
/// PERMISSION_DENIED, a Shopify 429, a dead socket — into one of these, so the
/// UI can say something true without knowing which backend is behind it. The
/// rule the whole layer exists to enforce: a raw exception string never reaches
/// a person.
library;

sealed class RepositoryException implements Exception {
  const RepositoryException(this.message, {this.cause});

  /// Developer-facing. User-facing copy is chosen by the UI, not carried here.
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The thing asked for does not exist.
///
/// This is the honest answer the prototype could not give: its lookups fell
/// back to a default record, so a bad deep link showed someone else's profile.
class NotFoundException extends RepositoryException {
  const NotFoundException(this.kind, this.id, {super.cause})
    : super('No $kind with id $id');

  /// What was being looked for: 'product', 'person', 'forum'.
  final String kind;
  final String id;
}

/// No usable connection.
class OfflineException extends RepositoryException {
  const OfflineException({super.cause}) : super('No connection');
}

/// Signed in, but not allowed. Distinct from being signed out, because the
/// remedy is different: one is "sign in", the other is "you cannot do this".
class PermissionException extends RepositoryException {
  const PermissionException(super.message, {super.cause});
}

/// Signed out, or the session expired, and the action needs an account.
class UnauthenticatedException extends RepositoryException {
  const UnauthenticatedException({super.cause}) : super('Not signed in');
}

/// Backing off. [retryAfter] when the backend told us how long.
class RateLimitException extends RepositoryException {
  const RateLimitException({this.retryAfter, super.cause})
    : super('Too many requests');

  final Duration? retryAfter;
}

/// The write was rejected for a reason the person can fix — a taken handle, an
/// out-of-stock variant, a review on something they did not buy.
class ValidationException extends RepositoryException {
  const ValidationException(super.message, {this.field, super.cause});

  final String? field;
}

/// Anything else the backend reported.
class BackendException extends RepositoryException {
  const BackendException(super.message, {this.code, super.cause});

  final String? code;
}
