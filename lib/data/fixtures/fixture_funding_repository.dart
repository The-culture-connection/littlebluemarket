import '../../models/funding.dart';
import '../repositories/funding_repository.dart';
import 'fixture_repositories.dart';

/// The demo backend's funding months.
///
/// Two of them on purpose. Last month has a bill, so the transparency block
/// can be seen as designed; the month before it has nothing, so the "—"
/// state can be seen too. A page that asks for money has to look right when
/// the figures are missing as well as when they are there, and that state is
/// otherwise only reachable on a fresh project.
class FixtureFundingRepository implements FundingRepository {
  FixtureFundingRepository(this._backend);

  final FixtureBackend _backend;

  static String get _thisMonth => Funding.monthOf(DateTime.now());
  static String get _lastMonth => Funding.previousMonthOf(_thisMonth);

  @override
  Future<Funding?> month(String month) {
    if (month == _lastMonth) {
      return _backend.delayed(
        Funding(
          month: month,
          raisedCents: 41800,
          budgetCents: 62000,
          donors: 212,
          costs: const {
            'Hosting & push': 28400,
            'Directory sync': 19600,
            'Town halls': 14000,
          },
        ),
      );
    }
    if (month == _thisMonth) {
      // This month has takings but no bill yet, which is the ordinary state
      // mid-month and the one the nudge's live number comes from.
      return _backend.delayed(
        Funding(month: month, raisedCents: 9300, budgetCents: 62000, donors: 47),
      );
    }
    return _backend.delayed(null);
  }
}
