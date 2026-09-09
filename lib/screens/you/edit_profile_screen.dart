import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/dev_error_sink.dart';
import '../../data/repositories/repositories.dart';
import '../../models/models.dart';
import '../../router/app_router.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/photo_source.dart';
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
  final _city = TextEditingController();
  final _newTag = TextEditingController();
  List<String>? _tags;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    _city.dispose();
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
    _city.text = me.cityState;
    _tags = List.of(me.tags);
  }

  bool _uploadingPhoto = false;

  /// Picks a photo and makes it the avatar on the spot: the upload writes
  /// the URL onto the profile, so the new face shows before Save.
  Future<void> _changePhoto() async {
    if (_uploadingPhoto) return;
    final source = await choosePhotoSource(context);
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (file == null) return;
      setState(() => _uploadingPhoto = true);
      final bytes = await file.readAsBytes();
      final repo = ref.read(profileRepositoryProvider);
      final url = await repo.uploadAvatar(
        bytes,
        contentType: pickedContentType(file),
      );
      await repo.updateProfile(ProfileEdit(avatarUrl: url));
      messenger.showSnackBar(const SnackBar(content: Text('Photo updated.')));
    } on RepositoryException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(describeError(error).body)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not get that photo: $error')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
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
              cityState: _city.text.trim(),
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
                  onPressed: _uploadingPhoto ? null : _changePhoto,
                  child: Text(
                    _uploadingPhoto ? 'Uploading…' : 'Change photo',
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
          LbmField(
            label: 'Bio',
            controller: _bio,
            maxLines: 4,
            helper:
                'Paste a web address (your shop, Instagram, a booking page) '
                'and it becomes a tappable link on your profile.',
          ),
          const SizedBox(height: 16),
          LbmField(
            label: 'City, State',
            controller: _city,
            hintText: 'Detroit, MI',
            helper: 'Near me measures from here, and your listings show it.',
          ),
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
          const SizedBox(height: 12),
          LbmCard(
            child: ListRow(
              leading: Icon(Icons.logout_rounded, color: c.ink3),
              title: const Text('Sign out'),
              subtitle: const Text('Back to the welcome screen'),
              onTap: () async {
                // Navigate on the next tick, after the sign-out has settled:
                // routing inside the auth stream's callback rebuilt providers
                // while this screen was being torn down.
                final router = ref.read(routerProvider);
                await ref.read(sessionProvider.notifier).signOut();
                await Future<void>.delayed(Duration.zero);
                router.go('/welcome');
              },
            ),
          ),
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
          // Orders and shipping are handled in Shipturtle, entirely; the app
          // only opens the door.
          const _ShipturtleRow(),
          const _DirectoryRow(),
        ],
      ),
    );
  }
}

class _ShipturtleRow extends ConsumerWidget {
  const _ShipturtleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return ListRow(
      title: const Text('Orders & shipping'),
      subtitle: const Text('Managed in Shipturtle'),
      trailing: Icon(Icons.open_in_new_rounded, size: 20, color: c.ink3),
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        var url = 'https://app.shipturtle.com/';
        try {
          url = (await ref.read(appConfigProvider.future)).shipturtleUrl;
        } on Object {
          // The default above is the real address; the config only confirms it.
        }
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          messenger.showSnackBar(SnackBar(content: Text('Could not open $url')));
        }
      },
    );
  }
}

/// littlebluecart.com and notifications. Everyone gets these rows: a seller
/// on the Market can be a customer of the directory, and the other way
/// round. The merchant's own account gets Admin as well.
class _DirectoryRow extends ConsumerWidget {
  const _DirectoryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final isAdmin = ref.watch(isAdminProvider);
    return RowStack(
      children: [
        if (isAdmin)
          ListRow(
            title: const Text('Admin'),
            subtitle: const Text('Announcements to everyone or to a role'),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: c.ink3,
            ),
            onTap: () => context.push('/you/admin'),
          ),
        ListRow(
          title: const Text('Little Blue Cart directory'),
          subtitle: const Text(
            'Your website orders and your business listing',
          ),
          trailing: Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3),
          onTap: () => context.push('/you/directory'),
        ),
        // Applying to the directory stays on the website: the plans, the
        // payment and Little Blue Cart's review live there.
        ListRow(
          title: const Text('List my business in the directory'),
          subtitle: const Text('Apply on littlebluecart.com'),
          trailing: Icon(Icons.open_in_new_rounded, size: 20, color: c.ink3),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            String url = '';
            try {
              url = (await ref.read(appConfigProvider.future))
                  .directoryAddListingUrl;
            } on Object {
              url = '';
            }
            final uri = Uri.tryParse(url);
            if (uri == null || url.isEmpty) {
              messenger.showSnackBar(
                const SnackBar(content: Text('That link is not set up yet.')),
              );
              return;
            }
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              messenger.showSnackBar(
                SnackBar(content: Text('Could not open $url')),
              );
            }
          },
        ),
        ListRow(
          title: const Text('Notifications'),
          subtitle: const Text('What this phone tells you about'),
          trailing: Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3),
          onTap: () => context.push('/you/notification-settings'),
        ),
      ],
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
          const _DirectoryRow(),
          ListRow(
            title: const Text('Sell with us'),
            subtitle: const Text(
              'Already a vendor, applying, or holding a claim code',
            ),
            trailing: Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: c.ink3,
            ),
            onTap: () => context.push('/you/sell'),
          ),
        ],
      ),
    );
  }
}

