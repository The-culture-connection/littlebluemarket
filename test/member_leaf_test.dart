import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_blue_market/models/models.dart';
import 'package:little_blue_market/theme/app_theme.dart';
import 'package:little_blue_market/widgets/member_leaf.dart';

Person _person({DateTime? memberUntil}) => Person(
  id: 'u1',
  name: 'Dee',
  handle: '@dee',
  tint: 0,
  bio: '',
  tags: const [],
  grossSalesCents: 0,
  purchases: 0,
  posts: 0,
  memberUntil: memberUntil,
);

Future<void> _pump(WidgetTester tester, Person person) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildLbmTheme(Brightness.light),
      home: Scaffold(body: Text.rich(memberNameSpan(person, person.name))),
    ),
  );
}

void main() {
  // What the monthly membership buys (App Review 3.1.2(c), 2026-10-05), so
  // it must be there for a member and for nobody else.
  testWidgets('a member wears the leaf by their name', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _person(memberUntil: DateTime.now().add(const Duration(days: 20))),
    );
    expect(find.byType(MemberLeaf), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Member')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a lapsed member and a non-member do not', (tester) async {
    await _pump(
      tester,
      _person(memberUntil: DateTime.now().subtract(const Duration(days: 1))),
    );
    expect(find.byType(MemberLeaf), findsNothing);

    await _pump(tester, _person());
    expect(find.byType(MemberLeaf), findsNothing);
  });
}
