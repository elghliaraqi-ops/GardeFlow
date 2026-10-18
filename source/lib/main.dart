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

/// Render a visible Flutter frame before waiting on plugins or the network.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GardeFlowBootstrap());
}

class GardeFlowBootstrap extends StatefulWidget {
  const GardeFlowBootstrap({super.key, this.bootstrap});

  /// Injectable to verify loading and recovery without a real backend.
  final Future<AppState> Function()? bootstrap;

  @override
  State<GardeFlowBootstrap> createState() => _GardeFlowBootstrapState();
}

class _GardeFlowBootstrapState extends State<GardeFlowBootstrap> {
  AppState? _state;
  String? _failedStep;
  String _currentStep = 'Ouverture de GardeFlow…';
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<AppState> _restoreSession() async {
    _reportStep('Initialisation locale');
    try {
      pdfrxFlutterInitialize();
    } catch (e) {
      debugPrint('Lecteur PDF facultatif indisponible: $e');
    }
    await initializeDateFormatting('fr_FR', null)
        .timeout(const Duration(seconds: 6));

    _reportStep('Initialisation de la session');
    // Supabase.initialize reads persisted auth; it does not require an
    // online profile request. Keep errors explicit rather than waiting forever.
    await SupabaseBackendService.instance.initialize()
        .timeout(const Duration(seconds: 12));

    _reportStep('Chargement des données locales');
    // AppState.load restores cached data first, asynchronously refreshing the
    // remote profile, roster and reminders only after the visible UI can paint.
    return AppState.load().timeout(const Duration(seconds: 20));
  }

  void _reportStep(String value) {
    if (mounted) setState(() => _currentStep = value);
  }

  void _start() {
    if (!mounted) return;
    final attempt = ++_attempt;
    setState(() => _failedStep = null);
    unawaited(_launch(attempt));
  }

  Future<void> _launch(int attempt) async {
    try {
      final state = await (widget.bootstrap?.call() ?? _restoreSession());
      if (!mounted || attempt != _attempt) return;
      setState(() => _state = state);
      if (widget.bootstrap == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.localSnapshotReadOnly) {
            huimMessengerKey.currentState?.showSnackBar(
              const SnackBar(
                duration: Duration(seconds: 12),
                content: Text(
                  'Mode protégé : les données locales n’ont pas pu être lues. '
                  'Elles sont conservées ; évitez les modifications hors ligne.',
                ),
              ),
            );
          }
          unawaited(_initializeOptionalServices());
        });
      }
    } catch (e, st) {
      debugPrint('GardeFlow startup [$_currentStep]: $e\n$st');
      if (!mounted || attempt != _attempt) return;
      setState(() => _failedStep = _currentStep);
    }
  }

  Future<void> _initializeOptionalServices() async {
    try {
      await NotificationService.instance.init()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Rappels facultatifs indisponibles: $e');
    }
    final state = _state;
    if (state != null) {
      try {
        await state.resumeNativeRemindersAfterStartup()
            .timeout(const Duration(seconds: 18));
      } catch (e) {
        debugPrint('Rappels différés après premier affichage: $e');
      }
    }
    try {
      await PushNotificationService.instance.initializeFirebase()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Firebase facultatif indisponible: $e');
    }
    try {
      await NotificationService.instance.prepareAlarmModePermissions()
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Autorisation alarme reportée: $e');
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
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.medical_services_outlined,
                      size: 56, color: Color(0xFF71E7BC)),
                  const SizedBox(height: 16),
                  const Text('GardeFlow',
                      style: TextStyle(color: Colors.white,
                          fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 20),
                  if (_failedStep == null) ...[
                    const CircularProgressIndicator(
                        color: Color(0xFF71E7BC)),
                    const SizedBox(height: 16),
                    Text(_currentStep,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFC5D9D1))),
                  ] else ...[
                    const Text('Démarrage interrompu',
                        style: TextStyle(color: Colors.white, fontSize: 17)),
                    const SizedBox(height: 8),
                    Text('Étape : $_failedStep',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFFC08C))),
                    const SizedBox(height: 12),
                    const Text('Aucune donnée locale n’a été supprimée.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFFC5D9D1))),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF176F55)),
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
