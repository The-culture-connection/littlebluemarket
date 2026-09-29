import '../../models/funding.dart';

/// What a month of running Little Blue Market cost and raised.
///
/// Its own interface, in its own file, because this phase is being built in
/// a parallel worktree and `repositories.dart` is the sort of file two
/// sessions both reach for. Wired in `data/providers.dart` like every other
/// repository, so nothing else about it is unusual.
abstract interface class FundingRepository {
  /// One month, or null when nothing has been recorded for it.
  ///
  /// Null rather than an empty [Funding] on purpose: "we have no figures for
  /// August" and "August cost nothing" are different, and only one of them
  /// may be shown as a bill.
  Future<Funding?> month(String month);
}
