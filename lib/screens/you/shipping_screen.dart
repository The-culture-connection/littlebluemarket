import 'package:flutter/material.dart';

import '../../data/fixtures.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';

/// Two segments: packages you sent as a seller, and packages coming to you as
/// a buyer.
class ShippingScreen extends StatefulWidget {
  const ShippingScreen({super.key});

  @override
  State<ShippingScreen> createState() => _ShippingScreenState();
}

class _ShippingScreenState extends State<ShippingScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sending = _tab == 0;
    final shipments = sending ? Fx.sending : Fx.receiving;

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Shipping'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SegmentedTabs(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            labels: [
              'Sending (${Fx.sending.length})',
              'Receiving (${Fx.receiving.length})',
            ],
            selected: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          for (final shipment in shipments)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _ShipmentCard(shipment: shipment),
            ),
          if (sending)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
              child: PillButton(
                'Buy a label',
                icon: Icons.add_rounded,
                style: PillStyle.ghost,
                onPressed: () {},
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            child: Text(
              'Opened from the ··· on your profile. Sending shows packages you '
              'shipped as a seller; Receiving shows what’s coming to you as a '
              'buyer.',
              style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final product = Fx.product(shipment.productId);
    final delivered = shipment.state.isDelivered;

    return LbmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: ProductArt(
                  product,
                  square: true,
                  borderRadius: const BorderRadius.all(Radius.circular(13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      shipment.party,
                      style: LbmText.tiny.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StateBadge(state: shipment.state),
            ],
          ),
          const SizedBox(height: 10),
          _TrackBar(step: shipment.step),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  shipment.tracking,
                  style: LbmText.xtiny.copyWith(
                    color: c.ink2,
                    // Tracking numbers line up because the figures are tabular,
                    // not because anything here is monospaced.
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                shipment.note,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: delivered ? c.sage : c.skyDeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final ShipmentState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg) = switch (state) {
      ShipmentState.delivered => (c.sageMist, c.sage),
      ShipmentState.labelCreated => (c.accentMist, c.accentText),
      _ => (c.skyMist, c.ink),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: LbmRadius.pillR),
      child: Text(
        state.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }
}

/// The four-step progress bar. Filled segments use the pure accent — no label
/// sits on them, so they do not need the deeper shade.
class _TrackBar extends StatelessWidget {
  const _TrackBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        for (var i = 1; i <= 4; i++) ...[
          if (i > 1) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i <= step ? c.accent : c.skyWash,
                borderRadius: LbmRadius.pillR,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
