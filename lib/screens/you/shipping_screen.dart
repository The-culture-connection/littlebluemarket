import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/product_art.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// Packages, in both directions — plus, for a seller, the tab where an order
/// becomes a shipment.
class ShippingScreen extends ConsumerStatefulWidget {
  const ShippingScreen({super.key});

  @override
  ConsumerState<ShippingScreen> createState() => _ShippingScreenState();
}

class _ShippingScreenState extends ConsumerState<ShippingScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isSeller = ref.watch(isSellerProvider);
    final receiving = ref.watch(receivingProvider);
    final sending = ref.watch(sendingProvider);

    // A buyer has nothing to send, so they get one tab rather than an empty one.
    final labels = isSeller
        ? const ['Receiving', 'Sending', 'Manage sales']
        : const ['Receiving'];
    final tab = _tab.clamp(0, labels.length - 1);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Packages'),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (labels.length > 1)
            SegmentedTabs(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              labels: labels,
              selected: tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          switch (tab) {
            0 => _Shipments(
              shipments: receiving,
              emptyTitle: 'Nothing on its way',
              emptyBody: 'What you buy shows up here with its tracking.',
            ),
            1 => Column(
              children: [
                const _RefreshShipments(),
                _Shipments(
                  shipments: sending,
                  emptyTitle: 'Nothing to send',
                  emptyBody: 'Orders you need to ship appear here.',
                ),
              ],
            ),
            _ => const _ManageSales(),
          },
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            child: Text(
              isSeller
                  ? 'Receiving is what is coming to you as a buyer. Sending is '
                        'what you shipped as a seller. Manage sales is where an '
                        'order gets its tracking number.'
                  : 'Everything on its way to you, with the tracking the seller '
                        'entered.',
              style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _Shipments extends StatelessWidget {
  const _Shipments({
    required this.shipments,
    required this.emptyTitle,
    required this.emptyBody,
  });

  final AsyncValue<List<Shipment>> shipments;
  final String emptyTitle;
  final String emptyBody;

  @override
  Widget build(BuildContext context) {
    return LbmAsync<List<Shipment>>(
      shipments,
      skeleton: const ListRowSkeleton(rows: 2, withAvatar: false),
      isEmpty: (shipments) => shipments.isEmpty,
      empty: LbmEmpty(title: emptyTitle, body: emptyBody),
      data: (shipments) => Column(
        children: [
          for (final shipment in shipments)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: _ShipmentCard(shipment: shipment),
            ),
        ],
      ),
    );
  }
}

/// Where a seller turns an order into a shipment.
///
/// This is the write that reaches the fulfilment provider, so the buyer's
/// Receiving tab and the courier both learn the same tracking number.
class _ManageSales extends ConsumerStatefulWidget {
  const _ManageSales();

  @override
  ConsumerState<_ManageSales> createState() => _ManageSalesState();
}

class _ManageSalesState extends ConsumerState<_ManageSales> {
  final _orderId = TextEditingController();
  final _tracking = TextEditingController();
  String _carrier = _carriers.first;
  bool _saving = false;
  String? _error;

  static const _carriers = ['USPS', 'UPS', 'FedEx', 'DHL', 'Local pickup'];

  @override
  void dispose() {
    _orderId.dispose();
    _tracking.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(fulfillmentRepositoryProvider)
          .addTracking(
            orderId: _orderId.text.trim(),
            trackingNumber: _tracking.text.trim(),
            carrier: _carrier,
          );
      if (!mounted) return;
      _orderId.clear();
      _tracking.clear();
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Tracking added. The buyer can see it.')),
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error).body;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: LbmCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mark an order shipped',
              style: LbmText.display.copyWith(fontSize: 17, color: c.ink),
            ),
            const SizedBox(height: 4),
            Text(
              'The number goes to the courier and to the buyer.',
              style: LbmText.tiny.copyWith(color: c.ink2),
            ),
            const SizedBox(height: 16),
            LbmField(label: 'Order number', controller: _orderId),
            const SizedBox(height: 14),
            LbmField(label: 'Tracking number', controller: _tracking),
            const SizedBox(height: 14),
            Text('Courier', style: LbmText.fieldLabel.copyWith(color: c.ink2)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final carrier in _carriers)
                  LbmChip(
                    carrier,
                    style: carrier == _carrier ? ChipStyle.on : ChipStyle.quiet,
                    onTap: () => setState(() => _carrier = carrier),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: LbmText.tiny.copyWith(color: c.clay)),
            ],
            const SizedBox(height: 18),
            PillButton(
              _saving ? 'Saving…' : 'Add tracking',
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShipmentCard extends ConsumerWidget {
  const _ShipmentCard({required this.shipment});

  final Shipment shipment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final product = ref.watch(productProvider(shipment.productId));
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
                child: LbmAsync<Product>(
                  product,
                  skeleton: const LbmSkeleton(height: 54, radius: 13),
                  errorBuilder: (_, _) =>
                      const LbmSkeleton(height: 54, radius: 13),
                  data: (product) => ProductArt(
                    product,
                    square: true,
                    borderRadius: const BorderRadius.all(Radius.circular(13)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LbmAsync<Product>(
                      product,
                      skeleton: const LbmSkeleton(width: 140, height: 13),
                      errorBuilder: (_, _) => const SizedBox.shrink(),
                      data: (product) => Text(
                        product.title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: c.ink,
                        ),
                      ),
                    ),
                    Text(
                      shipment.counterpartyName,
                      style: LbmText.tiny.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              LbmChip(
                shipment.state.label,
                fontSize: 10.5,
                style: delivered ? ChipStyle.on : ChipStyle.quiet,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TrackBar(step: shipment.step),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 14, color: c.ink3),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  shipment.tracking,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LbmText.xtiny.copyWith(
                    color: c.ink2,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            shipment.carrierNote,
            style: LbmText.xtiny.copyWith(color: c.ink3),
          ),
          if (shipment.payoutNote != null) ...[
            const SizedBox(height: 4),
            Text(
              shipment.payoutNote!,
              style: LbmText.xtiny.copyWith(
                fontWeight: FontWeight.w700,
                color: c.ink2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Four segments filling as the package moves.
class _TrackBar extends StatelessWidget {
  const _TrackBar({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      children: [
        for (var i = 1; i <= 4; i++) ...[
          if (i > 1) const SizedBox(width: 5),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i <= step ? c.sage : c.skyWash,
                borderRadius: LbmRadius.pillR,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Pulls the latest tracking and settlement words from Shipturtle now,
/// rather than at the next scheduled sync.
class _RefreshShipments extends ConsumerStatefulWidget {
  const _RefreshShipments();

  @override
  ConsumerState<_RefreshShipments> createState() => _RefreshShipmentsState();
}

class _RefreshShipmentsState extends ConsumerState<_RefreshShipments> {
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(fulfillmentRepositoryProvider).refreshShipments();
      messenger.showSnackBar(
        const SnackBar(content: Text('Checked with Shipturtle.')),
      );
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PillButton(
          _busy ? 'Checking…' : 'Check with Shipturtle',
          small: true,
          expand: false,
          style: PillStyle.quiet,
          onPressed: _busy ? null : _refresh,
        ),
      ),
    );
  }
}
