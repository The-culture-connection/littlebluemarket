import 'models.dart' show Person;

/// The shops on the market as an A to Z list (Grace, 2026-11-16: "Let
/// shoppers browse by vendor on the app in the market portion").
///
/// By the name on the shop, not the handle: a shop nobody has claimed has a
/// handle derived from its vendor string, and "@shop-the-note-house" is not
/// what anyone is looking for. Each shop once, a nameless one left out.
/// Pure.
List<Person> sortVendors(Iterable<Person> people) {
  final seen = <String>{};
  final out = [
    for (final p in people)
      if (p.isSeller && p.name.trim().isNotEmpty && seen.add(p.id)) p,
  ];
  out.sort((a, b) {
    final byName = vendorSortKey(a.name).compareTo(vendorSortKey(b.name));
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return out;
}

/// What a shop sorts by: lower case, with a leading "the " set aside, so
/// The Note House is under N where people look for it.
String vendorSortKey(String name) {
  final lower = name.trim().toLowerCase();
  return lower.startsWith('the ') ? lower.substring(4) : lower;
}

/// The letter a shop is filed under, or '#' for a name that starts with a
/// number or a symbol.
String vendorLetter(String name) {
  final key = vendorSortKey(name);
  if (key.isEmpty) return '#';
  final first = key[0].toUpperCase();
  return RegExp('[A-Z]').hasMatch(first) ? first : '#';
}

/// Shops whose name or handle contains [query], ignoring case. Empty query,
/// everything.
List<Person> filterVendors(List<Person> vendors, String query) {
  final q = query.trim().toLowerCase().replaceFirst('@', '');
  if (q.isEmpty) return vendors;
  return [
    for (final v in vendors)
      if (v.name.toLowerCase().contains(q) ||
          v.handle.toLowerCase().contains(q))
        v,
  ];
}
