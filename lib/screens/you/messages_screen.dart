import 'package:flutter/material.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// The direct-message inbox, reached from the envelope. Separate from the open
/// chatroom, which lives under Community.
class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Messages',
        actions: [
          CircleIconButton(
            icon: Icons.add_rounded,
            tooltip: 'New message',
            onPressed: () {},
          ),
        ],
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: SearchPill(label: 'Search messages'),
          ),
          LbmCard(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            child: RowStack(
              children: [
                for (final dm in Fx.dms) _DmRow(summary: dm),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            child: Text(
              'Direct messages only. The open chatroom lives under the '
              'Community tab.',
              style: LbmText.xtiny.copyWith(color: c.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DmRow extends StatelessWidget {
  const _DmRow({required this.summary});

  final DmSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final person = Fx.person(summary.personId);

    return ListRow(
      leading: Avatar(person),
      title: Text(person.name),
      subtitle: Text(
        summary.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.goToDm(person.id),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            summary.age,
            style: LbmText.xtiny.copyWith(
              color: c.ink2,
              fontFeatures: kTabularFigures,
            ),
          ),
          if (summary.unread > 0) ...[
            const SizedBox(height: 5),
            Container(
              constraints: const BoxConstraints(minWidth: 19),
              height: 19,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: c.accentDeep,
                borderRadius: LbmRadius.pillR,
              ),
              child: Text(
                '${summary.unread}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: c.accentInk,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
