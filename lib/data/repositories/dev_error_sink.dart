import 'dart:async';

/// True under `flutter test`. Dev-only surfaces check this so the smoke and
/// scaling suites render exactly what a release build renders.
const bool kUnderFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

/// One failure, as it happened, before anything friendly was made of it.
///
/// Pure Dart on purpose: the sink lives below the repository seam so every
/// backend can report into it, and nothing here knows about Flutter.
class DevErrorReport {
  DevErrorReport({
    required this.error,
    this.stack,
    this.operation,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final Object error;
  final StackTrace? stack;

  /// What was being attempted: `callable commerceAddLine`,
  /// `firestore users/{uid}`, `auth invalid-credential`, `uncaught`.
  final String? operation;
  final DateTime at;

  String get typeName => error.runtimeType.toString();

  /// The provider's own code when it has one (`failed-precondition`,
  /// `permission-denied`, `not-wired`), read without depending on any
  /// provider type.
  String? get code {
    try {
      final value = (error as dynamic).code;
      return value?.toString();
    } catch (_) {
      return null;
    }
  }

  String get message {
    try {
      final value = (error as dynamic).message;
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // Not every error has a message field.
    }
    return error.toString();
  }

  /// `FirebaseFunctionsException.details`, when the backend sent any.
  String? get details {
    try {
      final value = (error as dynamic).details;
      return value?.toString();
    } catch (_) {
      return null;
    }
  }
}

/// Where every raw failure goes in a debug build.
///
/// The user-facing copy in `describeError` deliberately hides the cause, so
/// a person building the app could not tell *what* failed. This keeps the
/// cause: repositories report the exception before translating it, the app
/// shows it on a dev-only strip, and a "Copy for Claude" button turns it
/// into a bug report. Off unless [enabled], which only `main()` sets in debug.
abstract final class DevErrorSink {
  static bool enabled = false;

  static const capacity = 50;

  static final _controller = StreamController<DevErrorReport>.broadcast();
  static final _recent = <DevErrorReport>[];

  /// The same exception often passes through two guards on its way up. It is
  /// reported once.
  static Expando<bool> _seen = Expando<bool>();

  static Stream<DevErrorReport> get stream => _controller.stream;

  static List<DevErrorReport> get recent => List.unmodifiable(_recent);

  static void report(Object error, [StackTrace? stack, String? operation]) {
    if (!enabled) return;
    try {
      if (_seen[error] == true) return;
      _seen[error] = true;
    } catch (_) {
      // Strings and numbers cannot carry an Expando; report them anyway.
    }
    final entry = DevErrorReport(error: error, stack: stack, operation: operation);
    _recent.add(entry);
    if (_recent.length > capacity) _recent.removeAt(0);
    if (!_controller.isClosed) _controller.add(entry);
  }

  static void clear() {
    _recent.clear();
    _seen = Expando<bool>();
  }
}
