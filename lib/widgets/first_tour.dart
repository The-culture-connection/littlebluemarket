import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// One page of the first-time tour.
class TourPage {
  const TourPage({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

/// What a new member is shown once, right after their profile is created.
const kTourPages = <TourPage>[
  TourPage(
    icon: Icons.grid_view_rounded,
    title: 'Welcome to Little Blue Market',
    body:
        'The Market is a grid of photographs from small makers and local '
        'businesses. Tap the pink cart on any picture to put it in yours. '
        'There are no likes here; carting something is how you say you '
        'love it, and the maker sees the number.',
  ),
  TourPage(
    icon: Icons.tag_rounded,
    title: 'Tags are places',
    body:
        'Tap any hashtag to see its collection. Follow one and new posts '
        'under it turn up in your Market; turn on Notify me and we will '
        'tell you. Near me shows the makers around your city.',
  ),
  TourPage(
    icon: Icons.forum_outlined,
    title: 'The community is in the Market',
    body:
        'Forum questions and the open chat turn up in the same grid as the '
        'products, and you can join in from there. Shoutouts name the makers '
        'you love. Tag someone with @ and they hear about it.',
  ),
  TourPage(
    icon: Icons.person_outline_rounded,
    title: 'The You tab',
    body:
        'What you bought, what you posted, and your reviews. The settings '
        'button is where you sell with us, join the Little Blue Cart '
        'directory, and choose what you are told about.',
  ),
  TourPage(
    icon: Icons.bug_report_outlined,
    title: 'Tell us what you think',
    body:
        'Diagnostics in Edit profile has a button for it. Report a bug or '
        'share a critique and a picture of the screen goes with it. This is '
        'a young app; your notes shape it.',
  ),
];

/// Shows the tour as a card over the current screen. Resolves when it is
/// closed, by Done or Skip.
Future<void> showFirstTour(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  useRootNavigator: true,
  builder: (_) => const _TourDialog(),
);

class _TourDialog extends StatefulWidget {
  const _TourDialog();

  @override
  State<_TourDialog> createState() => _TourDialogState();
}

class _TourDialogState extends State<_TourDialog> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == kTourPages.length - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final last = _index == kTourPages.length - 1;
    return Dialog(
      backgroundColor: c.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'A quick look around',
                    overflow: TextOverflow.ellipsis,
                    style: LbmText.tiny.copyWith(
                      color: c.ink2,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(last ? 'Close' : 'Skip'),
                ),
              ],
            ),
            SizedBox(
              height: 250,
              child: PageView.builder(
                controller: _pages,
                itemCount: kTourPages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final page = kTourPages[i];
                  return Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: LbmConst.welcomeBlue.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(page.icon, size: 32, color: c.ink),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        page.title,
                        textAlign: TextAlign.center,
                        style: LbmText.display.copyWith(
                          fontSize: 19,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            page.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: c.ink2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < kTourPages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? c.ink
                          : c.ink.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            PillButton(last ? 'Done' : 'Next', onPressed: _next),
          ],
        ),
      ),
    );
  }
}
