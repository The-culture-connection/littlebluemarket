import 'package:flutter/foundation.dart';

import 'formatting.dart';

/// How much someone wants removed.
///
/// Two answers, because the app stores are asked about two different things:
/// deleting the account itself, and deleting the data held about someone who
/// keeps their account.
enum DeletionScope {
  account('account', 'My account and everything with it'),
  data('data', 'My data, but keep my account');

  const DeletionScope(this.value, this.label);

  final String value;
  final String label;

  static DeletionScope fromValue(String? value) =>
      value == 'data' ? DeletionScope.data : DeletionScope.account;
}

/// Where a request stands with the merchant.
enum DeletionStatus {
  open('open', 'Open'),
  done('done', 'Done'),
  declined('declined', 'Declined');

  const DeletionStatus(this.value, this.label);

  final String value;
  final String label;

  static DeletionStatus fromValue(String? value) => values.firstWhere(
    (s) => s.value == value,
    orElse: () => DeletionStatus.open,
  );
}

/// Someone asking for their account or their data to be removed. Read only by
/// admins; filed from a page anyone can reach, signed in or not.
@immutable
class DeletionRequest {
  const DeletionRequest({
    required this.id,
    required this.email,
    required this.scope,
    required this.status,
    required this.createdAt,
    this.uid,
    this.name = '',
    this.note = '',
    this.handledAt,
  });

  final String id;

  /// The address to act on, and to write back to. Taken from the signed-in
  /// account when there is one, so it cannot be someone else's.
  final String email;

  /// Null when the request came from someone who was not signed in. The
  /// merchant matches the address by hand in that case.
  final String? uid;
  final String name;
  final DeletionScope scope;
  final String note;
  final DeletionStatus status;
  final DateTime createdAt;
  final DateTime? handledAt;

  bool get isOpen => status == DeletionStatus.open;
  String get age => Fmt.relative(createdAt);
}

/// What the page sends.
class NewDeletionRequest {
  const NewDeletionRequest({
    required this.email,
    required this.scope,
    this.note = '',
  });

  static const noteMax = 1000;

  final String email;
  final DeletionScope scope;
  final String note;

  /// A plausible address and a note inside the cap. Deliberately loose on the
  /// address: a typo is better handled by a person than refused by a regexp.
  bool get isValid {
    final trimmed = email.trim();
    return trimmed.length >= 5 &&
        trimmed.contains('@') &&
        trimmed.contains('.') &&
        !trimmed.contains(' ') &&
        note.length <= noteMax;
  }
}
