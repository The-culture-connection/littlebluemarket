import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/fixtures.dart';
import 'router/app_router.dart';
import 'state/session.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Hold the first frame until the welcome artwork is decoded. The still has to
  // be ready before the GIF is taken away or the handoff would flash, and the
  // native splash covers the wait.
  binding.deferFirstFrame();
  await _decode(
    Fx.still,
  ).timeout(const Duration(seconds: 5), onTimeout: () {});
  binding.allowFirstFrame();

  runApp(const ProviderScope(child: LittleBlueMarketApp()));
}

/// Resolves an asset image and completes once its first frame is available.
Future<void> _decode(String asset) {
  final completer = Completer<void>();
  final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void done() {
    if (!completer.isCompleted) completer.complete();
    stream.removeListener(listener);
  }

  listener = ImageStreamListener((_, _) => done(), onError: (_, _) => done());
  stream.addListener(listener);
  return completer.future;
}

class LittleBlueMarketApp extends ConsumerWidget {
  const LittleBlueMarketApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final override = ref.watch(sessionProvider).themeMode;

    return MaterialApp.router(
      title: 'Little Blue Market',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildLbmTheme(Brightness.light),
      darkTheme: buildLbmTheme(Brightness.dark),
      // Defaults to the system setting, as the prototype does.
      themeMode: switch (override) {
        Brightness.light => ThemeMode.light,
        Brightness.dark => ThemeMode.dark,
        null => ThemeMode.system,
      },
      builder: (context, child) {
        // Respect the reader's text size, but keep it inside a range the pill
        // tab bar and the fixed-height chrome can actually hold.
        final scale = MediaQuery.textScalerOf(
          context,
        ).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.35);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child!,
        );
      },
    );
  }
}
