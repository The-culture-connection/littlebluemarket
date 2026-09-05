import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Claiming a shop with a merchant-issued code.
///
/// This screen replaced a single row that turned selling on with one tap. That
/// row wrote `isSeller: true` from the client, and because the order pipeline
/// credits a sale to whichever account claims a vendor name, it was two writes
/// away from inheriting a stranger's catalogue and their revenue.
///
/// Nothing here decides anything. The code goes to a callable that checks the
/// verified email, consumes the code, reserves the vendor name and records the
/// grant in one transaction. This screen's whole job is to explain the result.
class ClaimShopScreen extends ConsumerStatefulWidget {
  const ClaimShopScreen({super.key});

  @override
  ConsumerState<ClaimShopScreen> createState() => _ClaimShopScreenState();
}

class _ClaimShopScreenState extends ConsumerState<ClaimShopScreen> {
  final _code = TextEditingController();
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    if (_code.text.trim().isEmpty || _working) return;
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final grant = await ref
          .read(profileRepositoryProvider)
          .requestSellerStatus(_code.text);
      if (!mounted) return;

      // Name the shop. A code issued against the wrong vendor record is the
      // one mistake the person can catch and we cannot.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You are now selling as ${grant.vendorName}.')),
      );
      context.pop();
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Start selling'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          LbmCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Little Blue Market sends you a claim code once your vendor '
                    'account is ready. Entering it here connects this profile to '
                    'your shop, so your products and sales show up on it.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: c.ink2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LbmField(
                    label: 'Claim code',
                    controller: _code,
                    hintText: 'The code we sent you',
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _claim(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                        color: c.clay,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  PillButton(
                    _working ? 'Checking…' : 'Claim my shop',
                    onPressed: _code.text.trim().isEmpty || _working
                        ? null
                        : _claim,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // TODO(copy): replace with the real route to a code — a support address
          // or a link — once the merchant decides how they are issued.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'No code yet? Get in touch with Little Blue Market and we will '
              'send you one.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}
