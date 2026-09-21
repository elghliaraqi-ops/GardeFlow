import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), _goNext);
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final signedIn = context.read<AppState>().currentUser != null;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, __) => signedIn ? const HomeScreen() : const AuthScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _goNext,
    child: Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const GardeFlowLogo(size: 88), const SizedBox(height: 24),
        Text('GardeFlow', style: Theme.of(context).textTheme.displayMedium),
        const SizedBox(height: 12),
        Text('Planning médical intelligent', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 32),
        Text('Le planning de garde pour garder le flow.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
      ]),
    )))),
  );
}
