import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/app_navigation.dart';
import 'services/push_notification_service.dart';
import 'services/supabase_backend_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Paint Flutter immediately: no I/O or network operation may hold the native
/// white launch window indefinitely before the first Flutter frame.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GardeFlowBootstrap());
}

/// Keeps startup visible and recoverable while restoring the authenticated
/// session. A failure never deletes the local planning or user preferences.
class GardeFlowBootstrap extends StatefulWidget {
  const GardeFlowBootstrap({super.key, this.bootstrap});

  /// Injectable for widget tests; normal startup uses [_restoreSession].
  final Future<AppState> Function()? bootstrap;

  @override
  State<GardeFlowBootstrap> createState() => _GardeFlowBootstrapState();
}

class _GardeFlowBootstrapState extends State<GardeFlowBootstrap> {
  AppState? _state;
  String? _error;
  bool _pdfReady = false;
  bool _backendReady = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    // Schedule after the first frame to guarantee a nonblank loading screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<AppState> _restoreSession() async {
    if (!_pdfReady) {
      // The PDF viewer is auxiliary and must never take down the whole app.
      try {
        pdfrxFlutterInitialize();
      } catch (e) {
        debugPrint('PDF bootstrap unavailable: $e');
      }
      _pdfReady = true;
    }
    await initializeDateFormatting('fr_FR', null);
    if (!_backendReady) {
      await SupabaseBackendService.instance.initialize()
          .timeout(const Duration(seconds: 15));
      _backendReady = true;
    }
    // Restores the verified profile and local data. Heavy roster sync and
    // reminder scheduling are nonblocking in AppState.load().
    return AppState.load().timeout(const Duration(seconds: 25));
  }

  void _start() {
    if (!mounted) return;
    final currentAttempt = ++_attempt;
    setState(() => _error = null);
    unawaited(_bootstrapAttempt(currentAttempt));
  }

  Future<void> _bootstrapAttempt(int currentAttempt) async {
    try {
      final loaded = await (widget.bootstrap?.call() ?? _restoreSession());
      if (!mounted || currentAttempt != _attempt) return;
      setState(() => _state = loaded);
      // Notifications/Firebase must not delay the login or home screen.
      if (widget.bootstrap == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_initializeOptionalServices());
        });
      }
    } catch (e, stack) {
      debugPrint('GardeFlow startup failed: $e\\n$stack');
      if (!mounted || currentAttempt != _attempt) return;
      setState(() => _error =
          'Impossible de terminer le démarrage. Vérifiez la connexion puis réessayez.');
    }
  }

  Future<void> _initializeOptionalServices() async {
    try {
      await NotificationService.instance.init()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Notification startup deferred: $e');
    }
    try {
      await PushNotificationService.instance.initializeFirebase()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Firebase startup deferred: $e');
    }
    // Preserve the alarm permission flow, without gating first paint.
    try {
      await NotificationService.instance.prepareAlarmModePermissions()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Alarm permission prompt deferred: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state != null) {
      return ChangeNotifierProvider.value(
        value: state,
        child: const HuimApp(),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GardeFlow',
      home: Scaffold(
        backgroundColor: const Color(0xFF071C19),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.medical_services_outlined,
                      size: 56, color: Color(0xFF71E7BC)),
                  const SizedBox(height: 16),
                  const Text('GardeFlow',
                      style: TextStyle(color: Colors.white,
                          fontSize: 29, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (_error == null) ...[
                    const CircularProgressIndicator(
                        color: Color(0xFF71E7BC)),
                    const SizedBox(height: 18),
                    const Text('Chargement de votre espace…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFC5D9D1),
                            fontSize: 14)),
                  ] else ...[
                    const Icon(Icons.wifi_off_rounded,
                        color: Color(0xFFFFC08C), size: 26),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 14)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF176F55)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Vos données enregistrées sur cet appareil sont conservées.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFAAC6BB), fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HuimApp extends StatelessWidget {
  const HuimApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appearanceTheme =
        context.select<AppState, String>((state) => state.appearanceTheme);
    AppColors.setAppearanceTheme(appearanceTheme);
    final darkMode = AppColors.isDarkMode;

    return MaterialApp(
      navigatorKey: huimNavigatorKey,
      scaffoldMessengerKey: huimMessengerKey,
      title: 'GardeFlow',
      debugShowCheckedModeBanner: false,
      theme: darkMode ? AppTheme.dark() : AppTheme.light(),
      themeAnimationDuration: const Duration(milliseconds: 220),
      themeAnimationCurve: Curves.easeOutCubic,
      locale: const Locale('fr', 'FR'),
      supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}
