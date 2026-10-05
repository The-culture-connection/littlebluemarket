import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/unverified_banner.dart';

/// Claiming a shop, by the email on the Shipturtle vendor account.
///
/// **The email is the only way in.** A Shipturtle vendor already has an
/// email on their vendor account, and confirming that address in the app is
/// the proof: `syncSellerStatus` matches it against the Shipturtle roster
/// and grants the vendor string their products carry. Nobody has to issue
/// anything, and a vendor approved at midnight can be selling at one past.
///
/// This screen used to offer a claim code and nothing else, with a TODO
/// about how codes would be handed out. That had it backwards twice over: it
/// sent every vendor to ask Grace for something they did not need, and it
/// invited anybody at all to sit here trying to claim somebody else's shop
/// (Grace, 2026-09-24). The field is gone. A refusal now says what to check
/// and who to ask, and offers nothing else to try.
///
/// The roster match still refuses three cases on purpose, because they need
/// a judgement rather than a rule: one email on two vendor companies, a
/// vendor with no products yet, and a vendor string another account already
/// holds. Those are settled by an admin on the admin website
/// (`vendor_approval.ts`), which is where the judgement belongs.
///
/// Nothing here decides anything. This screen's whole job is to explain the
/// result.
class ClaimShopScreen extends ConsumerStatefulWidget {
  const ClaimShopScreen({super.key, this.shopName = ''});

  /// The shop whose "Is this your shop?" was tapped, if it was tapped from a
  /// shop at all. Empty when somebody arrived here from Start selling.
  ///
  /// It exists so a refusal can name the shop. Grace, 2026-09-24: "can we
  /// also add a clear rejection when a person tries to claim a shop that is
  /// not theirs." Without it the screen can only say that this email is not
  /// on the vendor list, which is true but reads as a technical hiccup; with
  /// it the screen can say that this shop is not yours, which is the fact.
  ///
  /// It decides nothing. The grant is the Shipturtle roster match and
  /// nothing else, so a name typed into this query string buys no access.
  final String shopName;

  @override
  ConsumerState<ClaimShopScreen> createState() => _ClaimShopScreenState();
}

class _ClaimShopScreenState extends ConsumerState<ClaimShopScreen> {
  bool _checking = false;
  String? _error;
  SellerSyncResult? _result;

  /// The autonomous path: the address on the Shipturtle vendor account,
  /// confirmed in the app, is the claim.
  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(profileRepositoryProvider)
          .syncSellerStatus();
      // A grant lives on the token; refresh it so the Products tab appears
      // without a sign-out.
      await ref.read(sessionProvider.notifier).reloadUser();
      if (!mounted) return;
      setState(() => _result = result);
      final granted =
          result.status == SellerSyncStatus.granted ||
          result.status == SellerSyncStatus.alreadySeller;
      // Granted, but not the shop they tapped. Staying put is the whole
      // point: leaving for the profile would connect a different shop
      // without ever saying so, and they came here asking about this one.
      final wrongShop =
          granted &&
          widget.shopName.trim().isNotEmpty &&
          result.vendorName != null &&
          _SyncNote._key(result.vendorName!) !=
              _SyncNote._key(widget.shopName);
      if (granted && !wrongShop) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.vendorName == null
                  ? 'Your shop is connected.'
                  : 'You are now selling as ${result.vendorName}.',
            ),
          ),
        );
        context.go('/you');
      }
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final session = ref.watch(sessionProvider).value;
    final verified = session is MemberSession && session.emailVerified;

    return LbmScreen(
      appBar: const LbmAppBar(title: 'Start selling'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Step 0: the address has to be proven before anything is granted
          // against it. The whole scheme rests on it.
          const UnverifiedBanner(),
          LbmCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect my shop',
                    style: LbmText.display.copyWith(fontSize: 19, color: c.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you sell with Little Blue Market through Shipturtle, '
                    'use the same email here as on your vendor account. '
                    'Confirm it and tap below: we check the vendor list and '
                    'connect your shop, with its products and sales, to this '
                    'profile. No code needed.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: c.ink2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  PillButton(
                    _checking ? 'Checking…' : 'Connect my shop',
                    onPressed: !verified || _checking ? null : _check,
                  ),
                  if (!verified) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Confirm your email first (above).',
                      style: LbmText.xtiny.copyWith(color: c.ink3),
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    _SyncNote(
                      result: _result!,
                      shopName: widget.shopName,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _error!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                  color: c.clay,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Not a vendor yet? Apply on our website first. Once Little Blue '
              'Market approves you, come back and tap Connect my shop.\n\n'
              'Shops are connected by the email on the vendor account and '
              'nothing else, so nobody can claim a shop that is not theirs.',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Why the check did not connect a shop, in words the person can act on.
///
/// Only the unhappy cases reach here: a grant leaves the screen.
class _SyncNote extends StatelessWidget {
  const _SyncNote({required this.result, this.shopName = ''});

  final SellerSyncResult result;

  /// The shop they came from, when they came from one.
  final String shopName;

  /// Whether the shop that was granted is the shop they tapped.
  ///
  /// Compared the way the backend compares vendor strings, so "Found House
  /// Ceramics" and "found house ceramics" are the same shop and a stray
  /// space is not a refusal.
  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  /// The rejection, when somebody tried to claim a shop that is not theirs.
  ///
  /// Grace, 2026-09-24: "can we also add a clear rejection when a person
  /// tries to claim a shop that is not theirs." Said plainly and first,
  /// naming the shop, because the old wording ("we could not find a vendor
  /// account with this email") reads like something went wrong rather than
  /// like an answer. There is nothing to try again: the email on the
  /// Shipturtle vendor account is the only thing that connects a shop, so a
  /// second tap gives the same result.
  String? get _rejection {
    final shop = shopName.trim();
    if (shop.isEmpty) return null;

    return switch (result.status) {
      // Granted, but not this shop. The most confusing case to leave
      // unexplained: they are a seller, so the app changes around them, and
      // nothing says why it was not the shop they were looking at.
      SellerSyncStatus.granted || SellerSyncStatus.alreadySeller
          when result.vendorName != null &&
              _key(result.vendorName!) != _key(shop) =>
        '$shop is not your shop. The email on this profile belongs to '
            '${result.vendorName}, which is the shop that has been connected.',
      SellerSyncStatus.granted || SellerSyncStatus.alreadySeller => null,
      SellerSyncStatus.notFound =>
        '$shop is not your shop. It is connected by the email on its '
            'Shipturtle vendor account, and this profile\'s email is not that '
            'address. If $shop really is yours, sign in with the email on the '
            'vendor account, or get in touch with Little Blue Market.',
      SellerSyncStatus.undecided when result.note != null =>
        'We could not connect $shop to this profile, because ${result.note}. '
            'Get in touch with Little Blue Market and we will sort it out.',
      SellerSyncStatus.undecided =>
        'We could not connect $shop to this profile on its own. Get in touch '
            'with Little Blue Market and we will sort it out.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rejection = _rejection;
    if (rejection != null) {
      // Refusals are read in the same colour as any other thing that did not
      // work, so there is no mistaking it for a progress note.
      return Text(
        rejection,
        style: LbmText.xtiny.copyWith(
          color: c.clay,
          fontWeight: FontWeight.w700,
          height: 1.55,
        ),
      );
    }

    final text = switch (result.status) {
      SellerSyncStatus.granted ||
      SellerSyncStatus.alreadySeller => 'Your shop is connected.',
      // A refusal is a refusal. It says what to check and who to ask, and
      // offers nothing else to try: inviting a stranger to have another go
      // at somebody else's shop is the opposite of a guard (Grace,
      // 2026-09-24).
      SellerSyncStatus.notFound =>
        'We could not find a vendor account with this email. It has to be '
            'the same address as on your Shipturtle vendor account. If it is, '
            'get in touch with Little Blue Market and we will connect it.',
      SellerSyncStatus.undecided =>
        result.note == null
            ? 'We found your vendor account, but could not connect the shop '
                  'on its own. Get in touch with Little Blue Market and we '
                  'will do it for you.'
            : 'We found your vendor account, but could not connect the shop '
                  'on its own, because ${result.note}. Get in touch with '
                  'Little Blue Market and we will do it for you.',
    };
    return Text(
      text,
      style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.55),
    );
  }
}
