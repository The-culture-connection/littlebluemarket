import 'package:flutter/services.dart';

/// The small buzz when something the person did has landed (Grace,
/// 2026-10-21: "vibrations at major actions like adding to cart or leaving a
/// comment").
///
/// After the write succeeds, never on the tap: a buzz for a comment that then
/// fails to send tells the hand it went when it did not. One place, so every
/// major action feels the same and the strength is chosen once.
abstract final class LbmHaptics {
  /// Something added or sent: into the cart, a comment, a reply, a message,
  /// a post, a review, the handoff to checkout.
  static void done() => HapticFeedback.mediumImpact();
}
