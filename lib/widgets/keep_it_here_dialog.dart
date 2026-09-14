import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// The one thing a new member is asked, right after the tour.
///
/// Shown by the app shell the moment [showFirstTour] closes, whether that
/// was Done or Skip, so it is the last word of the first arrival. There is
/// no way out but the button: this is the platform's ask, not a tip, and it
/// is shown exactly once per phone (the same `Tips.firstTour` write that
/// follows the tour covers both).
Future<void> showKeepItHereDialog(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  useRootNavigator: true,
  builder: (_) => const _KeepItHereDialog(),
);

class _KeepItHereDialog extends StatelessWidget {
  const _KeepItHereDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final body = TextStyle(fontSize: 14, height: 1.5, color: c.ink2);

    return Dialog(
      backgroundColor: c.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: LbmConst.welcomeBlue.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.volunteer_activism_outlined,
                    size: 32,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Keeping Little Blue Cart alive',
                textAlign: TextAlign.center,
                style: LbmText.display.copyWith(fontSize: 20, color: c.ink),
              ),
              const SizedBox(height: 14),
              Text(
                'To keep Little Blue Cart alive, we ask buyers and sellers to '
                'keep transactions inside the platform where possible, and to '
                'report any seller or buyer who tries to push a purchase to '
                'another platform.',
                style: body,
              ),
              const SizedBox(height: 12),
              Text(
                'We also ask sellers to add their Little Blue Cart link to the '
                'bio on their profile, so shoppers can always find their way '
                'back to you.',
                style: body,
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.more_horiz_rounded, size: 17, color: c.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To report someone, tap the three dots on any post or '
                      'profile.',
                      style: LbmText.tiny.copyWith(color: c.ink3, height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              PillButton(
                'I understand',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
