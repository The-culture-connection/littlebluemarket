import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';
import '../data/repositories/dev_error_sink.dart';
import '../router/app_router.dart';

/// A reported failure plus where the app was when it happened.
@immutable
class DevErrorEntry {
  const DevErrorEntry({
    required this.report,
    required this.route,
    required this.backend,
  });

  final DevErrorReport report;
  final String route;
  final String backend;

  String get headline {
    return [report.typeName, ?report.code, ?report.operation].join(' · ');
  }
}

/// Whether the dev-only surfaces render at all.
///
/// Debug builds only, and never under `flutter test` — the smoke and scaling
/// suites must see exactly what a release build shows. A test that wants the
/// strip overrides this to true.
final devSurfaceEnabledProvider = Provider<bool>(
  (ref) => kDebugMode && !kUnderFlutterTest,
);

/// The last few failures, newest last.
class DevErrorsNotifier extends Notifier<List<DevErrorEntry>> {
  static const keep = 20;

  @override
  List<DevErrorEntry> build() {
    final subscription = DevErrorSink.stream.listen((report) {
      state = [
        ...state.skip(state.length >= keep ? state.length - keep + 1 : 0),
        DevErrorEntry(
          report: report,
          route: _currentRoute(),
          backend: ref.read(backendLabelProvider),
        ),
      ];
    });
    ref.onDispose(subscription.cancel);
    return const [];
  }

  String _currentRoute() {
    try {
      return ref
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .toString();
    } catch (_) {
      return '?';
    }
  }

  void dismissLatest() {
    if (state.isEmpty) return;
    state = state.sublist(0, state.length - 1);
  }

  void clear() => state = const [];
}

final devErrorsProvider =
    NotifierProvider<DevErrorsNotifier, List<DevErrorEntry>>(
      DevErrorsNotifier.new,
    );

/// The block that goes on the clipboard. Everything Claude needs to find the
/// failure, nothing it has to ask for.
String formatForClaude(DevErrorEntry entry) {
  final r = entry.report;
  final stack = r.stack?.toString().split('\n').take(8).join('\n  ');
  final buffer = StringBuffer()
    ..writeln('--- LBM dev error (paste to Claude) ---')
    ..writeln('when:      ${r.at.toIso8601String()}')
    ..writeln('backend:   ${entry.backend}')
    ..writeln('route:     ${entry.route}')
    ..writeln('operation: ${r.operation ?? '?'}')
    ..writeln('type:      ${r.typeName}')
    ..writeln('code:      ${r.code ?? '-'}')
    ..writeln('message:   ${r.message}')
    ..writeln('details:   ${r.details ?? '-'}');
  if (stack != null && stack.isNotEmpty) {
    buffer
      ..writeln('stack (top 8):')
      ..writeln('  $stack');
  }
  buffer.writeln('---------------------------------------');
  return buffer.toString();
}
