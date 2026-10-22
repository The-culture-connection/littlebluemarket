/// The colours a face or a forum is drawn in when there is no photograph.
///
/// The brand guide's eight colours, as plain ARGB ints so the data layer can
/// hand them out without Flutter (brand guide, 2026-10-22). The order is the
/// order of `LbmConst.makerTints`, so the two hash a given id to the same
/// colour.
const kAvatarTints = <int>[
  0xFF70A0D2, // blue
  0xFFD270D1, // orchid
  0xFFC49919, // gold
  0xFF89C9F4, // sky
  0xFFD3CABC, // sand
  0xFFB3BDCA, // grey-blue
  0xFFFAF2C6, // cream
  0xFF253856, // navy
];

/// A stable brand tint for [id]. The same hash every tint in the app has
/// always used, so a person keeps one colour from screen to screen.
int avatarTintFor(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return kAvatarTints[hash % kAvatarTints.length];
}

/// The tint to draw [id] in: the stored one if it is a brand colour,
/// otherwise the brand tint for its id.
///
/// Profiles and forums written before the brand guide carry a colour from
/// the old palette in their `tint` field. Rewriting every document for a
/// colour is not worth a migration; reading through this keeps them inside
/// the guide from the moment they are loaded.
int brandTint(int? stored, String id) =>
    stored != null && kAvatarTints.contains(stored)
    ? stored
    : avatarTintFor(id);
