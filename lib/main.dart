import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_services.dart';
import 'core/theme.dart';
import 'services/auth_service.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/profile_screen.dart';

Future<void> main() async {
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) => debugPrint('FlutterError: ${d.exceptionAsString()}');
    PlatformDispatcher.instance.onError = (e, s) {
      debugPrint('Uncaught: $e');
      return true;
    };
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await AppServices.create();
    runApp(const AegisApp());
    unawaited(S.auth.init());
    unawaited(S.assistant.init());
  }, (e, s) => debugPrint('Zone error: $e'));
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.settings,
      builder: (context, _) {
        final pal = AegisPalette.byId(S.settings.themeId);
        return MaterialApp(
          title: 'Aegis',
          debugShowCheckedModeBanner: false,
          theme: pal.theme,
          home: const _AuthGate(),
        );
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: S.auth,
      builder: (context, _) {
        switch (S.auth.status) {
          case AuthStatus.unknown:
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          case AuthStatus.signedOut:
            return const LoginScreen();
          case AuthStatus.signedIn:
            return S.auth.profile.complete
                ? const HomeScreen()
                : const ProfileScreen(firstRun: true);
          case AuthStatus.guest:
            return const HomeScreen();
        }
      },
    );
  }
}
