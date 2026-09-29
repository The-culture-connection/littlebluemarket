import 'profile_activity.dart';

/// The six sections of a profile whose visibility its owner controls.
///
/// The order here is the order of the chips, fixed rather than derived: a
/// profile whose tabs move about as someone flips switches is a profile you
/// cannot learn.
enum ProfileSection {
  bought('bought', 'Bought'),
  reviews('review', 'Reviews'),
  posts('post', 'Posts'),
  carts('cart', 'Carts'),
  threads('thread', 'Threads'),
  comments('comment', 'Comments');

  const ProfileSection(this.key, this.label);

  /// The key [ProfileSections.enabled] answers for.
  final String key;

  /// The chip.
  final String label;
}

/// Which sections a viewer gets, in the fixed order.
///
/// Your own profile keeps all six, the switched-off ones marked, because a
/// control whose effect you cannot see is one you cannot trust. Everybody
/// else gets only what you left on.
///
/// Bought is absent from somebody else's profile whatever the switch says:
/// `users/{uid}/purchases` is readable by its owner alone, so on another
/// person's profile there is nothing to draw. The switch still governs the
/// Bought number in their header, which is the part a visitor can see.
List<ProfileSection> visibleSections(
  ProfileSections sections, {
  required bool own,
}) => [
  for (final section in ProfileSection.values)
    if (own)
      section
    else if (section != ProfileSection.bought && sections.enabled(section.key))
      section,
];
