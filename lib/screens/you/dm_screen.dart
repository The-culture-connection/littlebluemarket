import 'package:flutter/material.dart';

import '../../data/fixtures/fixture_data.dart';
import '../../models/models.dart';
import '../../router/nav.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';

/// A one-to-one thread, reachable from the inbox and from Message on any
/// seller's feed.
class DmScreen extends StatefulWidget {
  const DmScreen({super.key, required this.personId});

  final String personId;

  @override
  State<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends State<DmScreen> {
  late final _messages = List<DmMessage>.of(Fx.dmThreadWith(widget.personId));

  void _send(String text) {
    setState(() {
      _messages.add(
        DmMessage(authorId: Fx.meId, createdAt: DateTime.now(), text: text),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final person = Fx.person(widget.personId);

    return LbmScreen(
      bottom: Composer(hintText: 'Message ${person.name}…', onSend: _send),
      appBar: LbmAppBar(
        titleSize: 16,
        title: person.name,
        actions: [
          CircleIconButton(
            icon: Icons.person_outline_rounded,
            tooltip: 'View feed',
            onPressed: () => context.goToSeller(person.id),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Center(
            child: Text(
              'Today',
              style: LbmText.xtiny.copyWith(color: c.ink2),
            ),
          ),
          const SizedBox(height: 14),
          for (final message in _messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _DmBubble(message: message, person: person),
            ),
          _OrderCard(),
        ],
      ),
    );
  }
}

class _DmBubble extends StatelessWidget {
  const _DmBubble({required this.message, required this.person});

  final DmMessage message;
  final Person person;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mine = message.authorId == Fx.meId;
    final author = mine ? Fx.me : person;

    return Row(
      textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Avatar(author, size: AvatarSize.xs),
        const SizedBox(width: 9),
        Flexible(
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: mine ? c.accentDeep : c.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(mine ? 18 : 6),
                    topRight: Radius.circular(mine ? 6 : 18),
                    bottomLeft: const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                  ),
                  boxShadow: mine ? null : c.shadowSoft,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: mine ? c.accentInk : c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message.time,
                style: LbmText.xtiny.copyWith(
                  color: c.ink2,
                  fontFeatures: kTabularFigures,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The order this conversation is about, pinned into the thread.
class _OrderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final product = Fx.product('p1');

    return LbmCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: ProductArt(
              product,
              square: true,
              borderRadius: const BorderRadius.all(Radius.circular(11)),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                  ),
                ),
                Text(
                  'Order #4471 · shipped today',
                  style: LbmText.xtiny.copyWith(color: c.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          LbmChip('View', onTap: () => context.goToPost(product.id)),
        ],
      ),
    );
  }
}
