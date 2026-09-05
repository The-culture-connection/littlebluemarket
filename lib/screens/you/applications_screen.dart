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
import '../../widgets/screen.dart';
import '../../widgets/sheets.dart';

/// The admin's queue of seller applications.
///
/// Approving asks for the vendor string the shop sells as, because that
/// string is the join key with the store and with Shipturtle, and a wrong
/// one puts every future product under a stranger. Declining asks for a
/// reason the applicant will read.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final isAdmin = ref.watch(isAdminProvider);
    final applications = ref.watch(applicationsProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Seller applications'),
      child: !isAdmin
          ? const LbmEmpty(
              title: 'Admins only',
              body: 'This account does not hold the admin claim.',
            )
          : LbmAsync<List<SellerApplication>>(
              applications,
              skeleton: const SizedBox.shrink(),
              onRetry: () => ref.invalidate(applicationsProvider),
              isEmpty: (all) => all.isEmpty,
              empty: const LbmEmpty(
                title: 'No applications waiting',
                body: 'New ones appear here as people apply.',
              ),
              data: (all) => ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 26),
                children: [
                  for (final app in all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ApplicationCard(application: app),
                    ),
                  Text(
                    'The vendor string must match what Shipturtle uses for '
                    "the shop's products. npm run shipturtle:vendors prints "
                    'it.',
                    style: LbmText.xtiny.copyWith(color: c.ink3, height: 1.5),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.application});

  final SellerApplication application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final app = application;
    return LbmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            app.shopName,
            style: LbmText.display.copyWith(fontSize: 18, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '${app.appliedEmail} · ${app.age} ago',
            style: LbmText.tiny.copyWith(color: c.ink2),
          ),
          if (app.storeUrl.isNotEmpty)
            Text(app.storeUrl, style: LbmText.tiny.copyWith(color: c.ink2)),
          if (app.vendorEmail.isNotEmpty)
            Text(
              'Shipturtle email: ${app.vendorEmail}',
              style: LbmText.tiny.copyWith(color: c.ink2),
            ),
          if (app.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(app.note, style: LbmText.tiny.copyWith(color: c.ink)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PillButton(
                'Approve…',
                small: true,
                expand: false,
                onPressed: () => _decide(context, ref, approve: true),
              ),
              PillButton(
                'Decline…',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: () => _decide(context, ref, approve: false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final controller = TextEditingController(
      text: approve ? application.shopName : '',
    );
    await showLbmSheet(context, (sheetContext) {
      final c = sheetContext.c;
      return _DecisionSheet(
        approve: approve,
        controller: controller,
        color: c,
        onSubmit: (value) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref
                .read(profileRepositoryProvider)
                .decideApplication(
                  application.uid,
                  approve: approve,
                  vendorName: approve ? value : null,
                  reason: approve ? null : value,
                );
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  approve
                      ? '${application.shopName} now sells as "$value".'
                      : 'Declined.',
                ),
              ),
            );
          } on RepositoryException catch (error) {
            messenger.showSnackBar(
              SnackBar(content: Text(describeError(error).body)),
            );
          }
        },
      );
    });
    controller.dispose();
  }
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({
    required this.approve,
    required this.controller,
    required this.color,
    required this.onSubmit,
  });

  final bool approve;
  final TextEditingController controller;
  final LbmColors color;
  final Future<void> Function(String value) onSubmit;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return LbmSheet(
      children: [
        Text(
          widget.approve ? 'Approve this shop' : 'Decline this application',
          style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
        ),
        const SizedBox(height: 6),
        Text(
          widget.approve
              ? 'The vendor string the shop sells as on the store, exactly. '
                    'It is what attributes every future product and sale.'
              : 'The applicant reads this.',
          style: LbmText.tiny.copyWith(color: c.ink2),
        ),
        const SizedBox(height: 14),
        LbmField(
          label: widget.approve ? 'Vendor string' : 'Reason',
          controller: widget.controller,
          autofocus: true,
          maxLines: widget.approve ? 1 : 3,
        ),
        const SizedBox(height: 14),
        PillButton(
          _busy
              ? 'Working…'
              : (widget.approve ? 'Approve and grant' : 'Decline'),
          onPressed: _busy
              ? null
              : () async {
                  final value = widget.controller.text.trim();
                  if (value.isEmpty) return;
                  setState(() => _busy = true);
                  await widget.onSubmit(value);
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ],
    );
  }
}
