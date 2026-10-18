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

/// The first Flutter frame is never gated by Firebase, notifications or network.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GardeFlowBootstrap());
}

/// Visible, retryable startup that never clears locally saved state.
class GardeFlowBootstrap extends StatefulWidget {
  const GardeFlowBootstrap({super.key, this.bootstrap});

  // Injected by widget tests; production uses _load().
  final Future<AppState> Function()? bootstrap;

  @override
  State<GardeFlowBootstrap> createState() => _GardeFlowBootstrapState();
}

class _GardeFlowBootstrapState extends State<GardeFlowBootstrap> {
  AppState? _ready;
  String? _errorCode;
  String _phase = 'Initialisation…';
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<AppState> _load(int attempt) async {
    // Auxiliary viewers and localization must not block native first paint.
    try {
      pdfrxFlutterInitialize();
    } catch (error) {
      debugPrint('PDF rendering deferred: $error');
    }
    _showPhase(attempt, 'Préparation des langues…');
    await initializeDateFormatting('fr_FR', null)
        .timeout(const Duration(seconds: 7));

    _showPhase(attempt, 'Connexion à votre session…');
    await SupabaseBackendService.instance.initialize()
        .timeout(const Duration(seconds: 12));

    _showPhase(attempt, 'Restauration de vos données…');
    // AppState.load restores the cache immediately; all remote profile
    // and planning refreshes are performed asynchronously.
    return AppState.load().timeout(const Duration(seconds: 12));
  }

  void _showPhase(int attempt, String phase) {
    if (!mounted || attempt != _attempt) return;
    setState(() => _phase = phase);
  }

  void _start() {
    if (!mounted) return;
    final attempt = ++_attempt;
    setState(() {
      _errorCode = null;
      _phase = 'Initialisation…';
    });
    unawaited(_completeStartup(attempt));
  }

  Future<void> _completeStartup(int attempt) async {
    try {
      final restored = await (widget.bootstrap?.call() ?? _load(attempt));
      if (!mounted || attempt != _attempt) return;
      setState(() => _ready = restored);
      if (widget.bootstrap == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_initializeOptionalServices(restored));
        });
      }
    } catch (error, stack) {
      debugPrint('GardeFlow bootstrap at $_phase: $error\n$stack');
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _errorCode = _phase.contains('langues')
            ? 'LANG'
            : _phase.contains('session')
                ? 'INIT'
                : 'CACHE';
      });
    }
  }

  Future<void> _initializeOptionalServices(AppState restored) async {
    try {
      await NotificationService.instance.init()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Optional reminders init: $e');
    }
    try {
      await PushNotificationService.instance.initializeFirebase()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Optional Firebase init: $e');
    }
    // Never wait for native scheduling when entering the home screen.
    unawaited(restored.resumeNativeReminders().catchError(
      (Object e, StackTrace stack) {
        debugPrint('Deferred reminder scheduling: $e');
      },
    ));
    try {
      await NotificationService.instance.prepareAlarmModePermissions()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('Optional alarm permissions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    if (ready != null) {
      return ChangeNotifierProvider.value(
        value: ready,
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
                      size: 54, color: Color(0xFF71E7BC)),
                  const SizedBox(height: 16),
                  const Text('GardeFlow',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 16),
                  if (_errorCode == null) ...[
                    const CircularProgressIndicator(
                        color: Color(0xFF71E7BC)),
                    const SizedBox(height: 18),
                    Text(_phase,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Color(0xFFC5D9D1), fontSize: 14)),
                  ] else ...[
                    const Icon(Icons.info_outline,
                        color: Color(0xFFFFC08C), size: 28),
                    const SizedBox(height: 12),
                    const Text(
                      'Le démarrage a été interrompu.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text('Diagnostic : $_errorCode',
                        style: const TextStyle(
                            color: Color(0xFFFFC08C), fontSize: 13)),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF176F55),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Vos données enregistrées sont conservées. '
                      'Transmettez le code diagnostic si le problème persiste.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFAAC6BB), fontSize: 12),
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
