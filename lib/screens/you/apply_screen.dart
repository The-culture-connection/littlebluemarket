import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Applying to sell, for someone with no claim code.
///
/// The form is short because the admin is the identity check: an approved
/// application becomes the same grant a claim code makes, as the vendor
/// string the admin names. The status card says where it stands, in the
/// admin's own words when it was declined.
class ApplyToSellScreen extends ConsumerStatefulWidget {
  const ApplyToSellScreen({super.key});

  @override
  ConsumerState<ApplyToSellScreen> createState() => _ApplyToSellScreenState();
}

class _ApplyToSellScreenState extends ConsumerState<ApplyToSellScreen> {
  final _shopName = TextEditingController();
  final _storeUrl = TextEditingController();
  final _vendorEmail = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_shopName, _storeUrl, _vendorEmail, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_shopName.text.trim().isEmpty) {
      setState(() => _error = 'Give your shop a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(profileRepositoryProvider)
          .applyToSell(
            SellerApplicationDraft(
              shopName: _shopName.text.trim(),
              storeUrl: _storeUrl.text.trim(),
              vendorEmail: _vendorEmail.text.trim(),
              note: _note.text.trim(),
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent. We will let you know.')),
      );
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final application = ref.watch(myApplicationProvider);

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Apply to sell'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          LbmAsync<SellerApplication?>(
            application,
            skeleton: const SizedBox.shrink(),
            errorBuilder: (_, _) => const SizedBox.shrink(),
            data: (existing) => existing == null
                ? _form(c)
                : _StatusCard(application: existing),
          ),
        ],
      ),
    );
  }

  Widget _form(LbmColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tell Little Blue Market about your shop. Once approved, your '
          'profile becomes a storefront: your products, your sales, and '
          'a way to add more from this app.',
          style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5),
        ),
        const SizedBox(height: 16),
        LbmCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LbmField(
                label: 'Shop name',
                controller: _shopName,
                readOnly: _busy,
              ),
              const SizedBox(height: 12),
              LbmField(
                label: 'Website or store link (optional)',
                controller: _storeUrl,
                keyboardType: TextInputType.url,
                readOnly: _busy,
              ),
              const SizedBox(height: 12),
              LbmField(
                label: 'Email you use with Shipturtle (optional)',
                controller: _vendorEmail,
                keyboardType: TextInputType.emailAddress,
                readOnly: _busy,
              ),
              const SizedBox(height: 12),
              LbmField(
                label: 'Anything else (optional)',
                controller: _note,
                maxLines: 3,
                readOnly: _busy,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: LbmText.tiny.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.clay,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              PillButton(
                _busy ? 'Sending…' : 'Send my application',
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Already have a claim code? Go back and choose Start selling.',
          style: LbmText.xtiny.copyWith(color: c.ink3),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.application});

  final SellerApplication application;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg) = switch (application.status) {
      ApplicationStatus.approved => (c.sageMist, c.sage),
      ApplicationStatus.declined => (c.skyWash, c.clay),
      ApplicationStatus.submitted => (c.accentMist, c.accentText),
    };
    return LbmCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: bg, borderRadius: LbmRadius.pillR),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                application.status.label,
                style: LbmText.xtiny.copyWith(
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            application.shopName,
            style: LbmText.display.copyWith(fontSize: 19, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(switch (application.status) {
            ApplicationStatus.submitted =>
              'Sent ${application.age} ago. Little Blue Market reviews '
                  'applications by hand, usually within a few days.',
            ApplicationStatus.approved =>
              'Approved. You sell as "${application.vendorName ?? application.shopName}". '
                  'Pull down on your profile if the Products tab has not '
                  'appeared yet.',
            ApplicationStatus.declined =>
              'Not approved${application.reason == null ? '' : ': ${application.reason}'}.',
          }, style: LbmText.tiny.copyWith(color: c.ink2, height: 1.5)),
          if (application.status == ApplicationStatus.approved) ...[
            const SizedBox(height: 12),
            PillButton(
              'Go to my profile',
              small: true,
              expand: false,
              onPressed: () => context.go('/you'),
            ),
          ],
        ],
      ),
    );
  }
}
