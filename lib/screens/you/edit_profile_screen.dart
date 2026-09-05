import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/dev_error_sink.dart';
import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';
import '../../widgets/skeleton.dart';

/// Photo, name, handle, bio, and the initiative hashtags on your storefront.
///
/// Two versions of this screen, chosen by whether you sell. The prototype had
/// one, which is why it offered every buyer a payouts-and-bank row.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _bio = TextEditingController();
  final _newTag = TextEditingController();
  List<String>? _tags;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _newTag.dispose();
    super.dispose();
  }

  /// Seeds the fields once the profile arrives, without clobbering an edit in
  /// progress if the profile stream emits again.
  void _seed(Person me) {
    if (_tags != null) return;
    _name.text = me.name;
    _handle.text = me.handle;
    _bio.text = me.bio;
    _tags = List.of(me.tags);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Actually persisted. The prototype's Save just popped.
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            ProfileEdit(
              name: _name.text.trim(),
              handle: _handle.text.trim(),
              bio: _bio.text.trim(),
              tags: _tags,
            ),
          );
      if (!mounted) return;
      context.canPop() ? context.pop() : context.go('/you');
    } on RepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error).body;
      });
    }
  }

  void _addTag() {
    final raw = _newTag.text.trim();
    if (raw.isEmpty) return;
    final tag = raw.startsWith('#') ? raw : '#$raw';
    setState(() {
      final current = _tags ?? <String>[];
      _tags = [...current, if (!current.contains(tag)) tag];
      _newTag.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final me = ref.watch(meProvider);
    final session = ref.watch(sessionProvider).value;
    final unverified = session is MemberSession && !session.emailVerified;

    if (me == null) {
      return const LbmScreen(
        appBar: LbmAppBar(title: 'Edit profile'),
        child: IdentitySkeleton(),
      );
    }
    _seed(me);

    return LbmScreen(
      appBar: LbmAppBar(
        title: 'Edit profile',
        actions: [
          PillButton(
            _saving ? 'Saving…' : 'Save',
            small: true,
            expand: false,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 26),
        children: [
          // Said here, before the wall: linking a shop account and claiming
          // a vendor both refuse an unconfirmed address.
          if (unverified) ...[
            LbmCard(
              child: ListRow(
                leading: Icon(Icons.mark_email_unread_outlined, color: c.clay),
                title: const Text('Confirm your email'),
                subtitle: const Text(
                  'Needed before your shop orders can link to this profile',
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: c.ink3,
                ),
                onTap: () {
                  final email =
                      ref.read(authServiceProvider).currentUser?.email ?? '';
                  context.push('/verify?email=${Uri.encodeComponent(email)}');
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          Center(
            child: Column(
              children: [
                Avatar(me, size: AvatarSize.lg),
                const SizedBox(height: 9),
                TextButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Photo upload arrives with storage.'),
                    ),
                  ),
                  child: Text(
                    'Change photo',
                    style: TextStyle(
                      fontFamily: kBodyFont,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: c.skyDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LbmField(label: 'Name', controller: _name),
          const SizedBox(height: 16),
          LbmField(
            label: me.isSeller ? 'Handle · also your storefront' : 'Handle',
            controller: _handle,
          ),
          const SizedBox(height: 16),
          LbmField(label: 'Bio', controller: _bio, maxLines: 3),
          const SizedBox(height: 16),
          Text(
            'Initiative hashtags',
            style: LbmText.fieldLabel.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in _tags ?? const <String>[])
                LbmChip(
                  tag,
                  style: ChipStyle.initiative,
                  trailingIcon: Icons.close_rounded,
                  onTap: () => setState(() => _tags = [...?_tags]..remove(tag)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                // The prototype's "+ add" chip was inert.
                child: LbmField(
                  controller: _newTag,
                  hintText: 'Add a hashtag',
                  pill: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 8),
              PillButton(
                'Add',
                small: true,
                expand: false,
                style: PillStyle.quiet,
                onPressed: _addTag,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            me.isSeller
                ? 'These show on your storefront and pull your posts into '
                      'initiative shelves.'
                : 'These pull your reviews and shoutouts into initiative '
                      'shelves.',
            style: LbmText.xtiny.copyWith(color: c.ink2, height: 1.55),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: LbmText.tiny.copyWith(color: c.clay)),
          ],
          const SizedBox(height: 16),
          if (me.isSeller) const _SellerRows() else const _BuyerRows(),
          // The hidden dev screen. Not in release builds, not under test.
          if (kDebugMode && !kUnderFlutterTest) ...[
            const SizedBox(height: 12),
            LbmCard(
              child: ListRow(
                title: const Text('Diagnostics (dev)'),
                subtitle: const Text(
                  'Who this phone thinks you are, and whether the backend '
                  'can reach the store',
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: c.ink3,
                ),
                onTap: () => context.push('/you/diagnostics'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a seller gets on top: payouts, and the sales side of shipping.
class _SellerRows extends StatelessWidget {
  const _SellerRows();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final chevron = Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3);

    return LbmCard(
      child: RowStack(
        children: [
          ListRow(
            title: const Text('Payouts & bank'),
            subtitle: const Text('Managed in your store'),
            trailing: chevron,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payouts are handled by your store account.'),
              ),
            ),
          ),
          ListRow(
            title: const Text('Sales & shipping'),
            subtitle: const Text('Add tracking, see what is waiting to go out'),
            trailing: chevron,
            onTap: () => context.push('/you/shipping'),
          ),
          const _AddressesRow(),
        ],
      ),
    );
  }
}

/// A buyer sees no payouts row, and gets a way into selling.
class _BuyerRows extends ConsumerStatefulWidget {
  const _BuyerRows();

  @override
  ConsumerState<_BuyerRows> createState() => _BuyerRowsState();
}

class _BuyerRowsState extends ConsumerState<_BuyerRows> {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      child: RowStack(
        children: [
          ListRow(
            title: const Text('Packages & tracking'),
            subtitle: const Text('What is on its way to you'),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: c.ink3,
            ),
            onTap: () => context.push('/you/shipping'),
          ),
          const _AddressesRow(),
          ListRow(
            title: const Text('Start selling'),
            subtitle: const Text('Connect the shop you already have'),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: c.ink3,
            ),
            onTap: () => context.push('/you/claim-shop'),
          ),
        ],
      ),
    );
  }
}

class _AddressesRow extends ConsumerWidget {
  const _AddressesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final addresses = ref.watch(addressesProvider);

    return ListRow(
      title: const Text('Shipping addresses'),
      // A real count, not the hardcoded "2 saved" the prototype showed.
      subtitle: Text(switch (addresses) {
        AsyncData(:final value) when value.isEmpty => 'None saved yet',
        AsyncData(:final value) => '${value.length} saved',
        AsyncError() => 'Could not load',
        _ => 'Loading…',
      }),
      trailing: Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3),
      onTap: () => context.push('/you/shipping'),
    );
  }
}
