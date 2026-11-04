import 'package:cloud_functions/cloud_functions.dart';

import '../../analytics/analytics.dart';

/// Sends a batch of [AnalyticsEvent]s to the `trackEvents` callable, which
/// stamps each with the signed-in member's id and the time it arrived.
AnalyticsSink firebaseAnalyticsSink(FirebaseFunctions functions) =>
    (batch) => functions.httpsCallable('trackEvents').call<Object?>({
      'events': [for (final event in batch) event.toJson()],
    });
