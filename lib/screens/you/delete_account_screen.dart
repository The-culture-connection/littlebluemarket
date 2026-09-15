import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../legal_links.dart';
import '../../data/repositories/dev_error_sink.dart';
import '../../models/models.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/async.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

/// Ask for an account, or the data behind it, to be removed.
///
/// Reachable by anyone, signed in or not, on the phone and on the website.
/// Both app stores require a page like this, and the website address of it is
/// what goes in their forms. A signed-in person's address is filled in and
/// locked, so a request from inside the app can never name somebody else.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _email = TextEditingController();
  final _note = TextEditingController();
  final _confirm = TextEditingController();
  final _password = TextEditingController();
  var _scope = DeletionScope.account;
  var _sending = false;
  var _sent = false;
  var _deleting = false;
  int? _deletedPosts;
  String? _error;
  var _prefilled = false;

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    _note.dispose();
    _confirm.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Sign in or create a profile: where somebody goes once their account
  /// is gone. pushReplacement rather than push, so Back cannot return to a
  /// page about deleting an account that no longer exists.
  void _startAgain() => context.go('/signin?create=1');

  /// Deletes it now. Every guard is the backend's: this only asks twice and
  /// then gets out of the way.
  Future<void> _deleteNow() async {
    if (_deleting) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _scope == DeletionScope.account
              ? 'Delete your account?'
              : 'Erase your information?',
        ),
        content: Text(
          _scope == DeletionScope.account
              ? 'Your profile, your posts and your sign-in go now, and cannot '
                    'be brought back. Orders stay as financial records, which '
                    'the privacy policy explains.'
              : 'Your bio, photo, hashtags and location are cleared now. Your '
                    'account stays, so you can keep buying.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              _scope == DeletionScope.account ? 'Delete for ever' : 'Erase it',
            ),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      // The password, here, now. The backend only deletes an account whose
      // token says it signed in minutes ago; a phone stays signed in for
      // weeks, so this is what makes that rule satisfiable without a
      // sign-out dance (Grace hit exactly that, 2026-09-14). It is also the
      // stronger check: knowing the password beats holding the phone.
      await ref.read(authServiceProvider).reauthenticate(_password.text);
      final posts = await ref
          .read(accountRepositoryProvider)
          .deleteMyAccount(scope: _scope, confirmation: _confirm.text);
      if (!mounted) return;
      setState(() => _deletedPosts = posts);
      // The account is gone, so the session has to go with it; staying
      // signed in to nothing is how a screen ends up showing errors.
      if (_scope == DeletionScope.account) {
        await ref.read(authServiceProvider).signOut();
        // And off this screen. Grace asked for the reroute (2026-09-14):
        // the account is gone, so every other screen behind this one is
        // about somebody who no longer exists, and leaving them on a page
        // titled 'Delete my account' is a strange goodbye. A moment on the
        // confirmation first, so they see that it worked.
        if (!kUnderFlutterTest) {
          await Future<void>.delayed(const Duration(seconds: 3));
          if (mounted) _startAgain();
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(accountRepositoryProvider)
          .requestDeletion(
            NewDeletionRequest(
              email: _email.text,
              scope: _scope,
              note: _note.text,
            ),
          );
      if (!mounted) return;
      setState(() => _sent = true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error).body);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final signedInEmail =
        ref.watch(authServiceProvider).currentUser?.email ?? '';
    if (!_prefilled && signedInEmail.isNotEmpty) {
      _prefilled = true;
      _email.text = signedInEmail;
    }
    final locked = signedInEmail.isNotEmpty;

    // A page of its own, outside the tab shell, so it brings its own
    // Scaffold: without one the text fields have no Material to sit on.
    return Scaffold(
      backgroundColor: c.paper,
      body: LbmScreen(
        appBar: const LbmAppBar(title: 'Delete my account or data'),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_sent) ...[
              LbmCard(
                color: c.sageMist,
                child: RowStack(
                  children: [
                    Text(
                      'Request received',
                      style: LbmText.display.copyWith(
                        fontSize: 19,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We will write to ${_email.text.trim()} when it is done, '
                      'usually within a few days and always within 30. If you '
                      'asked for your account to go, you can keep using it '
                      'until then.',
                      style: LbmText.body.copyWith(color: c.ink2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (_deletedPosts case final posts?) ...[
              LbmCard(
                color: c.sageMist,
                child: RowStack(
                  children: [
                    Text(
                      _scope == DeletionScope.account
                          ? 'Your account is gone'
                          : 'Your information is erased',
                      style: LbmText.display.copyWith(
                        fontSize: 19,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scope == DeletionScope.account
                          ? 'Your profile and sign-in have been removed, along '
                                'with ${posts == 1 ? '1 post' : '$posts posts'}. '
                                'You have been signed out. Orders stay as '
                                'financial records.'
                          : 'Your bio, photo, hashtags and location have been '
                                'cleared. Your account is still yours.',
                      style: LbmText.body.copyWith(color: c.ink2),
                    ),
                    // For anybody who does not want to wait for the reroute.
                    if (_scope == DeletionScope.account) ...[
                      const SizedBox(height: 14),
                      PillButton(
                        'Sign in or create a profile',
                        onPressed: _startAgain,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                'What would you like removed?',
                style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
              ),
              const SizedBox(height: 10),
              Text(
                locked
                    ? 'You are signed in, so this happens straight away and '
                          'cannot be undone.'
                    : 'Tell us which, and we will do it by hand and write '
                          'back. Nothing is removed the moment you tap send: '
                          'anyone can type an address here, so a person '
                          'checks it first.',
                style: LbmText.body.copyWith(color: c.ink2),
              ),
              const SizedBox(height: 18),
              for (final scope in DeletionScope.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ScopeRow(
                    scope: scope,
                    selected: _scope == scope,
                    onTap: () => setState(() => _scope = scope),
                  ),
                ),
              const SizedBox(height: 14),
              LbmField(
                label: 'The email address on the account',
                controller: _email,
                readOnly: locked,
                keyboardType: TextInputType.emailAddress,
                helper: locked
                    ? 'The address you are signed in with.'
                    : 'The address you signed up with, so we can find you.',
              ),
              const SizedBox(height: 12),
              LbmField(
                label: 'Anything else we should know (optional)',
                controller: _note,
                maxLines: 3,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: LbmText.tiny.copyWith(color: c.clay)),
              ],
              const SizedBox(height: 16),
              if (locked) ...[
                LbmField(
                  label: 'Your password',
                  controller: _password,
                  obscureText: true,
                  helper:
                      'Asked again here, so that holding an unlocked phone '
                      'is not enough to erase somebody.',
                ),
                const SizedBox(height: 12),
                LbmField(
                  label: 'Type $kDeleteConfirmation to confirm',
                  controller: _confirm,
                  helper:
                      'A word rather than a second tap, because this cannot '
                      'be undone.',
                ),
                const SizedBox(height: 14),
                PillButton(
                  _deleting
                      ? 'Deleting…'
                      : _scope == DeletionScope.account
                      ? 'Delete my account now'
                      : 'Erase my information now',
                  onPressed:
                      _deleting ||
                          _confirm.text.trim() != kDeleteConfirmation ||
                          _password.text.isEmpty
                      ? null
                      : _deleteNow,
                ),
                const SizedBox(height: 10),
                Text(
                  'Orders stay as financial records, which the privacy policy '
                  'explains. Everything else about you goes.',
                  style: LbmText.tiny.copyWith(color: c.ink3, height: 1.5),
                ),
              ] else
                PillButton(
                  _sending ? 'Sending…' : 'Send my request',
                  onPressed: _sending ? null : _send,
                ),
              const SizedBox(height: 22),
            ],
            const _WhatHappens(),
          ],
        ),
      ),
    );
  }
}

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.scope,
    required this.selected,
    required this.onTap,
  });

  final DeletionScope scope;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? c.skyWash : c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? c.skyDeep : c.skyMist,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? c.skyDeep : c.ink3,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scope.label,
                        style: LbmText.body.copyWith(
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(switch (scope) {
                        DeletionScope.account =>
                          'Your sign-in, your profile, your photos, your '
                              'posts and comments, your saved addresses and '
                              'your notification settings.',
                        DeletionScope.data =>
                          'Your profile details, photos and posts, while '
                              'your sign-in stays so you can start again.',
                      }, style: LbmText.tiny.copyWith(color: c.ink2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WhatHappens extends StatelessWidget {
  const _WhatHappens();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LbmCard(
      child: RowStack(
        children: [
          Text(
            'What we keep, and why',
            style: LbmText.display.copyWith(fontSize: 17, color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            'Orders stay. A completed order is a financial record for us and '
            'for the maker who sold to you, and the law asks us to keep it. '
            'Your own copy of it inside the app goes with your account. '
            'Everything else listed above is removed, usually within a few '
            'days and always within 30.',
            style: LbmText.body.copyWith(color: c.ink2),
          ),
          const SizedBox(height: 12),
          PillButton(
            'Read the privacy policy',
            small: true,
            expand: false,
            style: PillStyle.quiet,
            icon: Icons.open_in_new_rounded,
            onPressed: () => openLegalLink(LegalLinks.privacyPolicy),
          ),
        ],
      ),
    );
  }
}
