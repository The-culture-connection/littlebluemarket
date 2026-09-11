import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../legal_links.dart';
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
  var _scope = DeletionScope.account;
  var _sending = false;
  var _sent = false;
  String? _error;
  var _prefilled = false;

  @override
  void dispose() {
    _email.dispose();
    _note.dispose();
    super.dispose();
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
            ] else ...[
              Text(
                'What would you like removed?',
                style: LbmText.display.copyWith(fontSize: 21, color: c.ink),
              ),
              const SizedBox(height: 10),
              Text(
                'Tell us which, and we will do it by hand and write back. '
                'Nothing is removed the moment you tap send, because an account '
                'can have a shop and live orders behind it.',
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
