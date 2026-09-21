import 'package:flutter/material.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  await NotificationService.instance.init();
  await SupabaseBackendService.instance.initialize();
  await PushNotificationService.instance.initializeFirebase();
  final appState = await AppState.load();

  runApp(
    ChangeNotifierProvider.value(
      value: appState,
      child: const HuimApp(),
    ),
  );
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
