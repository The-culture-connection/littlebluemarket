import 'package:flutter/material.dart';

import '../../legal_links.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen.dart';

// The app's own terms, in the app.
//
// Not the Shopify store's policy page. That one is about buying and
// shipping, and says nothing about what people may post, how they are
// moderated, or how to report somebody. Apple asks for terms that do
// (guideline 1.2, "apps with user-generated content"), and the clause
// reviewers look for is the zero-tolerance one in section 4.
//
// Held in the app rather than fetched, on purpose: somebody agreeing to
// terms during sign-up should not be shown a spinner or a 404, and a
// reviewer on an aeroplane should still be able to read them.
//
// **Not written by a lawyer.** It covers the ground the app stores ask
// about and describes what this app actually does, which is the part only
// we can write. Have it read by somebody qualified before launch, and
// change [kTermsVersion] whenever the words change.

/// Bumped whenever the words below change, so what somebody agreed to can
/// be named later.
const kTermsVersion = '2026-09-14';

/// One part of the document.
class TermsSection {
  const TermsSection(this.heading, this.body);

  final String heading;
  final List<String> body;
}

const kTermsSections = <TermsSection>[
  TermsSection('1. Who this is between', [
    'These terms are an agreement between you and The Culture Connection '
        'Technology Solutions, which runs Little Blue Market and Little Blue '
        'Cart. They are not an agreement with Apple or Google, and neither '
        'company is responsible for this app or for anything in it.',
    'By creating a profile, or by using the app, you accept these terms. If '
        'you do not accept them, please do not use the app.',
  ]),
  TermsSection('2. Who may use it', [
    'You must be at least 13 years old. If you are under 18, you may use '
        'the app only with a parent or guardian who accepts these terms with '
        'you.',
    'You are responsible for what happens under your account, so keep your '
        'password to yourself. Tell us if you think somebody else has got '
        'into it.',
  ]),
  TermsSection('3. What you may do with the app', [
    'You have a personal, non-exclusive licence to use the app on devices '
        'you own or control, for your own use, whether you are here to buy '
        'or to sell. The app itself, its name and its artwork stay ours.',
    'You may not copy, resell or rent the app, take it apart to work out how '
        'it is built, use it to scrape or harvest other people\'s '
        'information, or use it to break the law.',
  ]),
  TermsSection('4. What you may not post, and our zero tolerance', [
    'There is no tolerance here for objectionable content or abusive '
        'behaviour. Post any of the following and your content may be '
        'removed and your account ended, without warning and without a '
        'refund of anything you have paid us:',
    '• Harassment, bullying, threats, or targeting somebody because of who '
        'they are.',
    '• Hate speech, or anything promoting violence or self-harm.',
    '• Sexual content, nudity, or anything involving a child in a sexual '
        'way, which we also report to the authorities.',
    '• Anything illegal, or the sale of anything you may not lawfully sell.',
    '• Somebody else\'s work, brand or photographs passed off as yours, or '
        'counterfeit goods.',
    '• Spam, scams, or attempts to move a sale off the platform to avoid '
        'its protections.',
    '• Anybody else\'s private information shared without their permission.',
  ]),
  TermsSection('5. Reporting, blocking and moderation', [
    'Every post and every profile carries a "…" menu with Report in it, and '
        'you can block anybody from your own screen at the same time. '
        'Blocking is private; the person is not told.',
    'We read reports and act on them, usually within a day. We may remove '
        'content or end an account when these terms are broken, and we do '
        'not have to explain every decision. We may also remove content for '
        'legal reasons, or when a platform we depend on requires it.',
    'If you think we have got something wrong, write to us and say so. We '
        'would rather fix a mistake than defend it.',
  ]),
  TermsSection('6. Your content stays yours', [
    'What you write, photograph and list stays yours. You give us '
        'permission to store it, show it in the app and on our websites, and '
        'to include it in the ordinary running and promotion of the '
        'marketplace, for as long as you keep it posted.',
    'You confirm that what you post is yours to post, and that showing it '
        'here breaks nobody else\'s rights.',
    'Delete a post and it goes. Delete your account and your profile, posts '
        'and comments go with it.',
  ]),
  TermsSection('7. Buying and selling', [
    'Orders are taken through our store and its own terms and refund policy '
        'apply to them, including delivery and returns. Prices and stock can '
        'change, and an obvious mistake in a price is not an offer we have '
        'to honour.',
    'Sellers are responsible for what they list, for making and sending it, '
        'and for their own taxes and licences. Sellers keep a shop link and '
        'may lose it if these terms are broken.',
    'Business listings shown under "Browse the directory" come from '
        'littlebluecart.com, and the business is responsible for what its '
        'listing says.',
    'We ask buyers and sellers to keep transactions on the platform where '
        'possible. Pushing a sale elsewhere to dodge fees or protections is '
        'a reason to lose an account.',
  ]),
  TermsSection('8. Adverts and announcements', [
    'You may see adverts and announcements in the app. An advert is marked '
        'as sponsored. We choose what appears and may refuse or remove any '
        'advert.',
  ]),
  TermsSection('9. Ending it, from either side', [
    'You may delete your account at any time in the app: Edit profile, then '
        'Delete my account. It happens straight away and cannot be undone. '
        'Orders are kept as financial records, which the privacy policy '
        'explains; everything else about you goes.',
    'We may suspend or end an account that breaks these terms, or that puts '
        'other people or the marketplace at risk.',
  ]),
  TermsSection('10. What we do not promise', [
    'The app is provided as it is. We keep it running as well as we can, '
        'but we do not promise it will always be available, error-free, or '
        'that anything you list will sell.',
    'We are not responsible for what other people post, or for what happens '
        'between a buyer and a seller beyond the part we run. Nothing here '
        'takes away rights you have under the law of your country that '
        'cannot be signed away, including consumer rights.',
    'As far as the law allows, our liability to you is limited to what you '
        'have paid us in the twelve months before the problem arose.',
  ]),
  TermsSection('11. Support, and reaching a person', [
    'Support for the app is ours, not Apple\'s or Google\'s. The quickest '
        'route is the small bug button inside the app, which sends us what '
        'you were looking at. You can also write to us:',
    LbmLinks.supportEmail,
  ]),
  TermsSection('12. Changes', [
    'We may change these terms as the app changes. When we do, the version '
        'date at the top of this page changes, and carrying on using the app '
        'means accepting the new version. A change that matters will be '
        'announced in the app.',
  ]),
  TermsSection('13. Apple and Google', [
    'Where you installed this app from Apple, you and we agree that: Apple '
        'has no obligation to provide support for it; Apple is not '
        'responsible for it or for any claim about it, including product '
        'liability, a failure to meet a legal requirement, or a claim under '
        'consumer protection law; and Apple may enforce these terms as a '
        'third party who benefits from them. You also confirm you are not in '
        'a country subject to a United States embargo and are not on a '
        'prohibited-parties list.',
  ]),
  TermsSection('14. The law that applies', [
    'These terms are governed by the law of the State of Michigan, United '
        'States, without affecting any right you have under the law of the '
        'place you live.',
  ]),
];

/// The terms, as a screen. Reachable from the sign-up tick, from Edit
/// profile, and at `/terms` from anywhere.
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // Its own Scaffold: this is opened from outside the tab shell (during
    // sign-up), where there is no Material for the text to sit on.
    return Scaffold(
      backgroundColor: c.paper,
      body: LbmScreen(
        appBar: const LbmAppBar(title: 'Terms of use'),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            LbmCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Little Blue Market',
                    style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Terms of use · version $kTermsVersion',
                    style: LbmText.tiny.copyWith(color: c.ink2),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The short version: be decent, post only what is yours, '
                    'and keep sales on the platform. Report anything that '
                    'should not be here and block anybody you would rather '
                    'not see. We remove content and end accounts over the '
                    'things in section 4.',
                    style: LbmText.body.copyWith(color: c.ink2, height: 1.55),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final section in kTermsSections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                child: Text(
                  section.heading,
                  style: LbmText.display.copyWith(fontSize: 16, color: c.ink),
                ),
              ),
              for (final paragraph in section.body)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    paragraph,
                    style: LbmText.body.copyWith(color: c.ink2, height: 1.55),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            LbmCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The privacy policy',
                    style: LbmText.display.copyWith(fontSize: 16, color: c.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'What we collect and why is a separate document, on the '
                    'website.',
                    style: LbmText.body.copyWith(color: c.ink2),
                  ),
                  const SizedBox(height: 12),
                  PillButton(
                    'Read the privacy policy',
                    style: PillStyle.ghost,
                    onPressed: () => openLegalLink(LegalLinks.privacyPolicy),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
