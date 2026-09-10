import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// On the web, the app inside a phone.
///
/// The screens were designed for a phone's width and every layout assumes
/// it. In a desktop browser this centres the app in a 430-point column with
/// rounded corners on a quiet ground, so it looks and behaves like the mobile
/// app rather than a stretched page. On a phone's browser, or any window
/// narrower than the column, it is invisible: the app fills the window as it
/// would on the device. Never rendered in the native apps.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  /// A large phone's logical width, and the tallest it is allowed to grow.
  static const double width = 430;
  static const double maxHeight = 932;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth <= width + 48;
        if (narrow) return child;

        final c = context.c;
        final height = constraints.maxHeight.clamp(0.0, maxHeight);
        final padding = constraints.maxHeight > maxHeight + 48 ? 24.0 : 0.0;
        return ColoredBox(
          color: c.skyMist,
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: padding),
              child: SizedBox(
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(padding > 0 ? 36 : 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.paper,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    // Screens read the window size through MediaQuery; inside
                    // the frame the window is the frame.
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: Size(width, height),
                        padding: EdgeInsets.zero,
                        viewPadding: EdgeInsets.zero,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
