import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/tokens.dart';

/// The sage leaf a member wears by their name.
///
/// What the monthly membership gives, besides keeping the app running, so
/// it has to be real and visible everywhere a name is: the profile, the
/// shop page, a post and a review (Grace, 2026-10-05, after App Review
/// asked what a subscriber receives for the price).
class MemberLeaf extends StatelessWidget {
  const MemberLeaf({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.eco_rounded,
      size: size,
      color: context.c.sage,
      semanticLabel: 'Member',
    );
  }
}

/// [name], with the leaf after it when [person] is a member. A span rather
/// than a row so a long name still wraps and a centred name stays centred.
InlineSpan memberNameSpan(Person person, String name, {double leafSize = 16}) {
  return TextSpan(
    text: name,
    children: [
      if (person.isMember)
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(left: 5),
            child: MemberLeaf(size: leafSize),
          ),
        ),
    ],
  );
}
