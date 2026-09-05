import 'package:flutter/foundation.dart';

/// One line of the backend health check.
@immutable
class HealthCheckItem {
  const HealthCheckItem({
    required this.name,
    required this.ok,
    required this.summary,
    this.fix,
  });

  final String name;
  final bool ok;
  final String summary;

  /// What to do about it, when [ok] is false.
  final String? fix;
}

/// What the deployed backend can and cannot reach, as it sees it.
@immutable
class HealthReport {
  const HealthReport({
    required this.project,
    required this.at,
    required this.checks,
  });

  final String project;
  final DateTime at;
  final List<HealthCheckItem> checks;

  bool get allOk => checks.every((c) => c.ok);
}

/// Who the phone thinks it is, from the token and the profile.
@immutable
class AuthFacts {
  const AuthFacts({
    required this.backend,
    this.uid,
    this.email,
    this.isAnonymous = false,
    this.emailVerified = false,
    this.isSeller = false,
    this.isAdmin = false,
    this.isLinked = false,
  });

  final String backend;
  final String? uid;
  final String? email;
  final bool isAnonymous;
  final bool emailVerified;

  /// From the `seller` custom claim on the token, not from any document.
  final bool isSeller;
  final bool isAdmin;

  /// Whether `linkAccounts` has run for this account.
  final bool isLinked;
}
