import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/repositories.dart';
import '../state/providers.dart';
import 'async.dart';
import 'primitives.dart';

/// Announcement and advert copy, with the `@profiles` and `#hashtags` in it
/// picked out and tappable.
///
/// Grace, 2026-09-24: "the ability to @profiles in announcements or
/// advertisements, also hashtags". A post has carried both for a long time;
/// these two drew them as plain grey text, so naming a shop in an advert
/// did nothing.
///
/// [mentions] is what the backend resolved when the copy was written:
/// handle, lowercased, to the uid it meant at the time. Preferred over
/// looking the handle up now, because handles change and an advert outlives
/// the moment it was composed — an advert that ran in March should still
/// open the right shop in September. The live lookup is the fallback, for
/// anything written before this existed.
class NamedText extends ConsumerWidget {
  const NamedText(
    this.text, {
    super.key,
    this.mentions = const {},
    this.style,
    this.tagColor,
    required this.onOpenProfile,
    required this.onOpenTag,
  });

  final String text;
  final Map<String, String> mentions;
  final TextStyle? style;
  final Color? tagColor;

  /// Given a uid. The caller decides how to get there, because a popup has
  /// to take itself down first and a list row does not.
  final ValueChanged<String> onOpenProfile;

  /// Given the tag as written, including its `#`.
  final ValueChanged<String> onOpenTag;

  Future<void> _openMention(
    BuildContext context,
    WidgetRef ref,
    String handle,
  ) async {
    final known = mentions[handle.toLowerCase()];
    if (known != null && known.isNotEmpty) {
      onOpenProfile(known);
      return;
    }
    // Written before mentions were resolved, or the handle has since moved
    // to somebody else. Either way, the handle as typed is all there is.
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final person = await ref
          .read(profileRepositoryProvider)
          .personByHandle(handle);
      if (person == null) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Nobody here is @$handle.')),
        );
        return;
      }
      onOpenProfile(person.id);
    } on RepositoryException catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HashtagText(
      text,
      style: style,
      tagColor: tagColor,
      onTagTap: onOpenTag,
      onMentionTap: (handle) => _openMention(context, ref, handle),
    );
  }
}
