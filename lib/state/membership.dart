import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/billing/billing_service.dart';
import 'providers.dart';
import 'session.dart';

/// The monthly membership, as the app sees it.
///
/// Two questions, kept apart on purpose. **Can this phone offer it** is a
/// store question: does the product exist for this platform and does the
/// store answer. **Is this person a member** is a server answer, read off
/// `users/{uid}.memberUntil`, which nothing on the phone can write.

/// The store product id for the platform this build is on, or empty.
///
/// The two stores do not have to agree on an identifier and here they do not,
/// so this picks rather than derives. Empty on the web, which has no store.
final membershipProductIdProvider = Provider<String>((ref) {
  final config = ref.watch(appConfigProvider).value;
  if (config == null || kIsWeb) return '';
  return Platform.isIOS || Platform.isMacOS
      ? config.membershipAppleProductId
      : config.membershipPlayProductId;
});

/// What the store charges, or null when there is nothing to offer.
///
/// Null is the answer that hides the card, and it covers every reason at
/// once: no product id configured, no store on this device, a store that has
/// never heard of the product. A price the app made up would be a promise it
/// cannot keep.
final membershipOfferProvider = FutureProvider<MembershipOffer?>((ref) async {
  final productId = ref.watch(membershipProductIdProvider);
  if (productId.isEmpty) return null;
  return ref.watch(billingServiceProvider).offer(productId);
});

/// Whether this person's membership is good right now.
///
/// Read from the person, which the server wrote. A membership that has run
/// out simply stops being true on its own, with no sweeper job needed,
/// because the date is the answer.
final isMemberProvider = Provider<bool>((ref) {
  return ref.watch(meProvider)?.isMember ?? false;
});

/// When it renews, for the line under the card.
final memberUntilProvider = Provider<DateTime?>((ref) {
  final me = ref.watch(meProvider);
  return me != null && me.isMember ? me.memberUntil : null;
});
