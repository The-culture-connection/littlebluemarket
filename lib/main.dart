import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'app_assets.dart';
import 'data/firebase/firebase_bootstrap.dart';
import 'data/firebase/firebase_push_service.dart';
import 'data/repositories/dev_error_sink.dart';
import 'platform/url_strategy.dart';
import 'router/app_router.dart';
import 'state/providers.dart';
import 'state/push_coordinator.dart';
import 'state/session.dart';
import 'theme/app_theme.dart';
import 'widgets/dev_error_surface.dart';
import 'widgets/feedback_button.dart';
import 'widgets/phone_frame.dart';
import 'widgets/splash_overlay.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  // Developer builds (LBM_DEV=true) keep every raw failure, so the dev strip
  // can say what broke and "Copy for Claude" can turn it into a bug report. A
  // plain `flutter run` is the production app and never enables the sink;
  // widget tests never run main().
  if (kLbmDev) {
    DevErrorSink.enabled = true;
    final presentError = FlutterError.onError;
    FlutterError.onError = (details) {
      presentError?.call(details);
      DevErrorSink.report(details.exception, details.stack, 'FlutterError');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      DevErrorSink.report(error, stack, 'uncaught');
      return false;
    };
  }

  // Web addresses without the '#', so a link to a page lands on that page.
  // Must run before the router reads the address.
  useAppUrlStrategy();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Hold the first frame until the welcome artwork is decoded. The still has to
  // be ready before the GIF is taken away or the handoff would flash, and the
  // native splash covers the wait.
  binding.deferFirstFrame();
  await Future.wait([
    _decode(LbmAssets.welcomeStill),
    _decode(LbmAssets.splash),
  ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
  binding.allowFirstFrame();

  // Firebase comes up only for a live build, so a fixture build needs no
  // configuration and pays no start-up cost.
  if (resolveBackend() == Backend.live) {
    await initializeFirebase(useEmulators: useFirebaseEmulators);
    // A background push has nothing to do in Dart (the system shows it), but
    // the handler must exist or the plugin logs a warning on every one.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(lbmBackgroundMessageHandler);
    }
  }

  runApp(ProviderScope(retry: lbmRetry, child: const LittleBlueMarketApp()));
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
    final override = ref.watch(themeModeProvider);
    // Registers the phone for push once a member is signed in and opens
    // the route a tapped banner names. No UI of its own.
    ref.watch(pushCoordinatorProvider);

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
          // Both dev overlays render nothing in release and under test. The
          // splash artwork holds for a moment on launch; the bug button sits
          // over every screen and photographs what is under it.
          // On the web the whole app sits inside a phone-sized frame.
          child: PhoneFrame(
            child: SplashOverlay(
              child: DevErrorSurface(
                child: Stack(
                  children: [
                    // A tap anywhere outside a text field puts the keyboard
                    // away. iPhones have no back button to do it with, and
                    // without this every form kept the keyboard up until the
                    // person found somewhere to scroll.
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () {
                        final focus = FocusManager.instance.primaryFocus;
                        if (focus != null && focus.context != null) {
                          focus.unfocus();
                        }
                      },
                      child: FeedbackLayer(router: router, child: child!),
                    ),
                    const DevBackendBadge(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
