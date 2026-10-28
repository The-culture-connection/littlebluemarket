// QA harness hooks, ported from the Empower Health suite (2026-10-22).
// Compiled in only with --dart-define=QA_HARNESS=true (the Railway QA build,
// deploy/qa/Dockerfile); every entry point is a pass-through otherwise.
//
// The harness page (deploy/qa/harness) hosts the app in an iframe sized to a
// real phone viewport and drives it over postMessage:
//   host -> app: config (text scale, Bold Text, safe areas, keyboard,
//                platform), audit, navigate, screenshot, highlight, inspect,
//                flash, ping
//   app -> host: ready, metrics, log, error, nav, audit, inspect, screenshot
//
// Where Empower Health finds its tabs through its own navigation scope, this
// app is all go_router: the address says which tab is showing, and opening a
// screen is `router.go`.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import 'layout_auditor.dart';
import 'widget_index.g.dart';
import 'qa_bridge_stub.dart' if (dart.library.js_interop) 'qa_bridge_web.dart';

class QaDeviceConfig {
  const QaDeviceConfig({
    this.device = 'Browser',
    this.textScale = 1.0,
    this.boldText = false,
    this.safeTop = 0,
    this.safeBottom = 0,
    this.keyboard = false,
    this.keyboardHeight = 336,
    this.platform = TargetPlatform.iOS,
    this.dark = false,
  });

  final String device;
  final double textScale;
  final bool boldText;
  final double safeTop;
  final double safeBottom;
  final bool keyboard;
  final double keyboardHeight;
  final TargetPlatform platform;

  /// The phone in dark mode (Grace, 2026-10-28). Applied as the app's own
  /// theme choice rather than through MediaQuery, because MaterialApp picks
  /// its theme above the point where the simulated device is applied.
  final bool dark;

  static TargetPlatform _platform(Object? v) =>
      v == 'android' ? TargetPlatform.android : TargetPlatform.iOS;

  static double _num(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? fallback;
  }

  static bool _bool(Object? v) => v == true || v == 'true' || v == '1';

  factory QaDeviceConfig.fromMap(Map<String, dynamic> m) => QaDeviceConfig(
    device: (m['device'] ?? 'Browser').toString(),
    textScale: _num(m['textScale'] ?? m['ts'], 1.0),
    boldText: _bool(m['boldText'] ?? m['bold']),
    safeTop: _num(m['safeTop'] ?? m['top'], 0),
    safeBottom: _num(m['safeBottom'] ?? m['bottom'], 0),
    keyboard: _bool(m['keyboard'] ?? m['kb']),
    keyboardHeight: _num(m['keyboardHeight'] ?? m['kbh'], 336),
    platform: _platform(m['platform']),
    dark: _bool(m['dark']),
  );

  /// Initial config from the iframe URL so the first frame is already right.
  factory QaDeviceConfig.fromUri(Uri uri) =>
      QaDeviceConfig.fromMap(Map<String, dynamic>.from(uri.queryParameters));

  MediaQueryData apply(MediaQueryData mq) {
    final insetBottom = keyboard ? keyboardHeight : 0.0;
    return mq.copyWith(
      textScaler: TextScaler.linear(textScale),
      boldText: boldText,
      viewPadding: EdgeInsets.only(top: safeTop, bottom: safeBottom),
      // Like iOS: the keyboard consumes the home-indicator inset.
      padding: EdgeInsets.only(
        top: safeTop,
        bottom: math.max(0, safeBottom - insetBottom),
      ),
      viewInsets: EdgeInsets.only(bottom: insetBottom),
    );
  }
}

class QaHarness {
  QaHarness._();

  static const bool enabled = bool.fromEnvironment('QA_HARNESS');

  static final ValueNotifier<QaDeviceConfig> config = ValueNotifier(
    enabled ? QaDeviceConfig.fromUri(Uri.base) : const QaDeviceConfig(),
  );
  static final ValueNotifier<bool> highlight = ValueNotifier(false);
  static final ValueNotifier<bool> inspect = ValueNotifier(false);
  static final ValueNotifier<List<QaIssue>> issues = ValueNotifier(const []);
  static final ValueNotifier<Rect?> selected = ValueNotifier(null);

  static final GlobalKey _appKey = GlobalKey(debugLabel: 'qa-app');
  static String _route = '/';
  static String _lastAuditSignature = '';
  static Timer? _auditTimer;
  static GoRouter? _router;

  /// The tabs, in the order of the shell's branches (Tabs in app_shell.dart).
  static const _tabRoots = ['/market', '/community', '/you'];
  static const _tabNames = ['Market', 'Community', 'You'];

  /// Matches the clamp in lib/main.dart's MaterialApp.builder.
  static const _minScale = 0.85;
  static const _maxScale = 1.35;

  /// Runs [appMain] inside a zone that mirrors print/errors to the harness.
  static void run(Future<void> Function() appMain) {
    if (!enabled) {
      appMain();
      return;
    }
    runZonedGuarded(
      () {
        WidgetsFlutterBinding.ensureInitialized();
        _install();
        appMain();
      },
      (error, stack) => _postError('Uncaught: $error', '$error\n$stack'),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          qaPost({'type': 'log', 'level': 'print', 'message': line});
          parent.print(zone, line);
        },
      ),
    );
  }

  /// The app's router, so the harness can read the address and open
  /// screens. Called from the app's build; safe to call more than once.
  static void attachRouter(GoRouter router) {
    if (!enabled || identical(router, _router)) return;
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = router;
    router.routerDelegate.addListener(_onRouteChanged);
    _onRouteChanged();
  }

  static void _onRouteChanged() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final router = _router;
      if (router == null) return;
      final uri = router.routerDelegate.currentConfiguration.uri;
      _route = uri.toString();
      qaPost({
        'type': 'nav',
        'action': 'go',
        'route': _route,
        'screens': _visibleScreens(),
      });
      _scheduleAudit();
    });
  }

  static void _install() {
    debugDefaultTargetPlatformOverride = config.value.platform;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      var detail = _normalizePaths(details.toString());
      // Web builds have no creation locations; map the widget chain
      // ("Row <- Padding <- _CartLineRow <- ...") to project source instead.
      final chain = detail.split('\n').where((l) => l.contains('←')).join(' ');
      final widgets = qaProjectWidgetsInChain(chain);
      if (widgets.isNotEmpty) {
        detail = 'Project widgets: ${widgets.join(', ')}\n\n$detail';
      }
      _postError(details.exceptionAsString(), detail);
      previousFlutterError?.call(details);
    };
    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _postError('Async: $error', '$error\n$stack');
      return previousPlatformError?.call(error, stack) ?? false;
    };

    qaListen(_onHostMessage);
    SchedulerBinding.instance.addPersistentFrameCallback(
      (_) => _scheduleAudit(),
    );
    SchedulerBinding.instance.addPostFrameCallback((_) {
      qaPost({'type': 'ready'});
      _postMetrics();
    });
  }

  static void _onHostMessage(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'ping':
        qaPost({'type': 'ready'});
        _postMetrics();
      case 'config':
        final next = QaDeviceConfig.fromMap(
          Map<String, dynamic>.from(m['config'] as Map),
        );
        final platformChanged = next.platform != config.value.platform;
        config.value = next;
        if (platformChanged) {
          debugDefaultTargetPlatformOverride = next.platform;
          WidgetsBinding.instance.reassembleApplication();
        }
        SchedulerBinding.instance.addPostFrameCallback((_) => _postMetrics());
        WidgetsBinding.instance.scheduleFrame();
      case 'audit':
        _runAudit(force: true);
      case 'navigate':
        _navigate(Map<String, dynamic>.from((m['target'] as Map?) ?? const {}));
      case 'screenshot':
        unawaited(_captureScreenshot(m['requestId']));
      case 'highlight':
        highlight.value = m['on'] == true;
        if (highlight.value) _runAudit(force: true);
      case 'inspect':
        inspect.value = m['on'] == true;
        if (!inspect.value) selected.value = null;
      case 'flash':
        final r = m['rect'];
        if (r is Map) {
          selected.value = Rect.fromLTWH(
            (r['x'] as num).toDouble(),
            (r['y'] as num).toDouble(),
            (r['w'] as num).toDouble(),
            (r['h'] as num).toDouble(),
          );
        }
    }
  }

  static void _scheduleAudit() {
    _auditTimer?.cancel();
    _auditTimer = Timer(const Duration(milliseconds: 900), () => _runAudit());
  }

  static void _runAudit({bool force = false}) {
    List<QaIssue> found;
    try {
      found = qaRunAudit();
    } catch (e) {
      qaPost({
        'type': 'log',
        'level': 'warn',
        'message': 'Layout audit failed: $e',
      });
      return;
    }
    final screens = _visibleScreens();
    final signature =
        '${screens.join(',')}#${found.map((i) => i.signature).join(';')}';
    if (!force && signature == _lastAuditSignature) return;
    _lastAuditSignature = signature;
    issues.value = found;
    qaPost({
      'type': 'audit',
      'route': _route,
      'screens': screens,
      'issues': found.map((i) => i.toJson()).toList(),
    });
  }

  static void _postMetrics() {
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) return;
    final view = views.first;
    final c = config.value;
    qaPost({
      'type': 'metrics',
      'width': view.size.width,
      'height': view.size.height,
      'dpr': view.flutterView.devicePixelRatio,
      'textScale': c.textScale,
      'textScaleEffective': c.textScale.clamp(_minScale, _maxScale),
      'boldText': c.boldText,
      'safeTop': c.safeTop,
      'safeBottom': c.safeBottom,
      'keyboard': c.keyboard ? c.keyboardHeight : 0,
      'platform': c.platform == TargetPlatform.android ? 'android' : 'ios',
      'dark': c.dark,
      'route': _route,
    });
  }

  static void _postError(String summary, String detail) {
    qaPost({
      'type': 'error',
      'summary': summary,
      'detail': detail.length > 6000 ? '${detail.substring(0, 6000)}…' : detail,
      'route': _route,
    });
  }

  static String _normalizePaths(String text) => text.replaceAllMapped(
    RegExp(r'(?:file|org-dartlang-app|https?):\/\/[^\s:]*?\/(lib\/[^\s:]+)'),
    (m) => m.group(1)!,
  );

  /// The tab whose branch the address is in: 0 Market, 1 Community, 2 You.
  static int? _currentTab() {
    final path = Uri.tryParse(_route)?.path ?? _route;
    for (var i = 0; i < _tabRoots.length; i++) {
      if (path == _tabRoots[i] || path.startsWith('${_tabRoots[i]}/')) {
        return i;
      }
    }
    return null;
  }

  /// Project screens the person can currently see.
  ///
  /// Walks the element tree and skips what is not on screen: an Offstage or
  /// invisible subtree, the unselected children of an IndexedStack (the
  /// shell's other tabs) and routes under an opaque one, which the Navigator
  /// keeps alive with their tickers off.
  static List<String> _visibleScreens() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];
    final screenName = RegExp(r'Screen$');
    final names = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) return;
      if (w is Visibility && !w.visible) return;
      if (w is TickerMode && !w.enabled) return;
      final name = qaTypeName(w);
      if (screenName.hasMatch(name) &&
          !names.contains(name) &&
          qaWidgetIndex.containsKey(name)) {
        names.add(name);
      }
      if (w is IndexedStack) {
        var i = 0;
        e.visitChildElements((child) {
          if (i++ == (w.index ?? 0)) visit(child);
        });
        return;
      }
      e.visitChildElements(visit);
    }

    visit(root);
    // Name the tab too, so a screen with no Screen class is still placed.
    final tab = _currentTab();
    if (tab != null) names.insert(0, '${_tabNames[tab]} tab');
    return names;
  }

  /// The theme the app is drawn in: the QA page's Dark mode switch when the
  /// harness is on, otherwise whatever the app chose for itself.
  static Widget themed(
    ThemeMode appMode,
    Widget Function(ThemeMode mode) build,
  ) {
    if (!enabled) return build(appMode);
    return ValueListenableBuilder<QaDeviceConfig>(
      valueListenable: config,
      builder: (context, c, _) =>
          build(c.dark ? ThemeMode.dark : ThemeMode.light),
    );
  }

  /// Wraps the app below MaterialApp: applies the simulated device to
  /// MediaQuery (before the app's own text-scale clamp) and adds the
  /// highlight / inspect overlay.
  static Widget wrapApp(
    BuildContext context,
    Widget Function(MediaQueryData mediaQuery) build,
  ) {
    if (!enabled) return build(MediaQuery.of(context));
    return ValueListenableBuilder<QaDeviceConfig>(
      valueListenable: config,
      builder: (context, c, _) => _QaOverlay(
        appKey: _appKey,
        child: build(c.apply(MediaQuery.of(context))),
      ),
    );
  }

  /// Opens the screen a checklist item is about: an address with `route`,
  /// or a tab's root with `tab` (0 Market, 1 Community, 2 You). `go`, not
  /// `push`, so the back stack is that screen's own, as if reached by hand.
  static void _navigate(Map<String, dynamic> target) {
    final router = _router;
    if (router == null) return;
    final route = target['route'];
    final tab = target['tab'];
    final where = route is String && route.isNotEmpty
        ? route
        : tab is num && tab >= 0 && tab < _tabRoots.length
        ? _tabRoots[tab.toInt()]
        : null;
    if (where == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => router.go(where));
  }

  /// PNG of the app as rendered (without the harness overlay), plus the
  /// context needed to file a bug and reopen its screen.
  static Future<void> _captureScreenshot(Object? requestId) async {
    try {
      final boundary = _appKey.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('app not rendered yet');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final size = Size(image.width / 2, image.height / 2);
      image.dispose();
      if (bytes == null) throw StateError('could not encode PNG');
      qaPost({
        'type': 'screenshot',
        'requestId': requestId,
        'png': base64Encode(bytes.buffer.asUint8List()),
        'width': size.width,
        'height': size.height,
        'route': _route,
        'tab': _currentTab(),
        'screens': _visibleScreens(),
        'issues': issues.value.map((i) => i.toJson()).toList(),
      });
    } catch (e) {
      qaPost({'type': 'screenshot', 'requestId': requestId, 'error': '$e'});
    }
  }

  static void _inspectAt(Offset position) {
    final box = _appKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final info = qaInspectAt(box, position);
    if (info == null) return;
    final r = info['rect']! as Map<String, double>;
    selected.value = Rect.fromLTWH(r['x']!, r['y']!, r['w']!, r['h']!);
    qaPost({'type': 'inspect', 'route': _route, 'info': info});
  }
}

class _QaOverlay extends StatelessWidget {
  const _QaOverlay({required this.appKey, required this.child});

  final GlobalKey appKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: appKey, child: child),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              QaHarness.highlight,
              QaHarness.issues,
              QaHarness.selected,
            ]),
            builder: (context, _) => CustomPaint(
              painter: _QaPainter(
                issues: QaHarness.highlight.value
                    ? QaHarness.issues.value
                    : const [],
                selected: QaHarness.selected.value,
              ),
            ),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: QaHarness.inspect,
          builder: (context, on, _) => on
              ? Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) => QaHarness._inspectAt(e.position),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// The harness's own marks over the app. Fixed colours on purpose: they
/// belong to the testing tool, not the app, and must read the same in light
/// and dark themes.
class _QaPainter extends CustomPainter {
  _QaPainter({required this.issues, required this.selected});

  final List<QaIssue> issues;
  final Rect? selected;

  static const _p0 = Color(0xFFE5484D);
  static const _p1 = Color(0xFFF59E0B);
  static const _pick = Color(0xFF2F80ED);

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < issues.length; i++) {
      final issue = issues[i];
      final color = issue.severity == 'P0' ? _p0 : _p1;
      canvas.drawRect(
        issue.rect,
        Paint()..color = color.withValues(alpha: 0.12),
      );
      canvas.drawRect(
        issue.rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final label = TextPainter(
        text: TextSpan(
          text: ' ${i + 1} ',
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final origin = Offset(
        issue.rect.left.clamp(0.0, math.max(0.0, size.width - label.width)),
        (issue.rect.top - label.height).clamp(
          0.0,
          math.max(0.0, size.height - label.height),
        ),
      );
      canvas.drawRect(origin & label.size, Paint()..color = color);
      label.paint(canvas, origin);
      label.dispose();
    }
    if (selected != null) {
      canvas.drawRect(selected!, Paint()..color = _pick.withValues(alpha: 0.2));
      canvas.drawRect(
        selected!,
        Paint()
          ..color = _pick
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_QaPainter old) =>
      old.issues != issues || old.selected != selected;
}
