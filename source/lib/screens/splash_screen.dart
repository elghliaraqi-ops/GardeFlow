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
    Future.delayed(const Duration(milliseconds: 2600), _goNext);
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final signedIn = context.read<AppState>().currentUser != null;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, animation, __) => signedIn ? const HomeScreen() : const AuthScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _goNext,
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.85, -0.75),
                  radius: 1.25,
                  colors: [Color(0xFFDDEEFF), Color(0xFFF7FAFF), Color(0xFFF0F6FD)],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.40,
                widthFactor: 1,
                child: ShaderMask(
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.white, Colors.white],
                    stops: [0, 0.32, 1],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: Opacity(
                    opacity: 0.24,
                    child: Image.asset(
                      'assets/branding/login_urgences.jpg',
                      fit: BoxFit.cover,
                      alignment: Alignment.center,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -90,
              right: -130,
              child: Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brand.withOpacity(0.10), width: 34),
                ),
              ),
            ),
            Positioned(
              bottom: 85,
              left: -130,
              child: Container(
                width: 290,
                height: 290,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.brand.withOpacity(0.08), width: 26),
                ),
              ),
            ),
            SafeArea(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 950),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(offset: Offset(0, 18 * (1 - value)), child: child),
                  );
                },
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 430,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GardeFlowLogo(size: 108),
                                SizedBox(height: 18),
                                RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontFamily: 'SpaceGrotesk',
                                      fontSize: 48,
                                      height: 1.0,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.8,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Garde',
                                        style: TextStyle(
                                          color: Color(0xFF0B633D),
                                        ),
                                      ),
                                      TextSpan(
                                        text: 'Flow',
                                        style: TextStyle(
                                          color: Color(0xFFD94A43),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Planning médical intelligent',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'SpaceGrotesk',
                                    fontSize: 16.5,
                                    height: 1.15,
                                    letterSpacing: 2.0,
                                    color: Color(0xFF315C49),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 18),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 58,
                                      height: 1.6,
                                      color: Color(0xFF62B88D),
                                    ),
                                    SizedBox(width: 12),
                                    Icon(
                                      Icons.monitor_heart_outlined,
                                      size: 24,
                                      color: Color(0xFF2F9B67),
                                    ),
                                    SizedBox(width: 12),
                                    Container(
                                      width: 58,
                                      height: 1.6,
                                      color: Color(0xFF62B88D),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 15),
                                Text(
                                  'LE PLANNING DE GARDE POUR GARDER LE FLOW',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'SpaceGrotesk',
                                    fontSize: 10.5,
                                    height: 1.3,
                                    letterSpacing: 2.0,
                                    color: Color(0xFF466D5B),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 26),
                            Text(
                              'AU SERVICE DES SOIGNANTS\nAU SERVICE DES PATIENTS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 12.0,
                                height: 1.55,
                                letterSpacing: 2.35,
                                color: Color(0xFF0B633D),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 9),
                            Container(
                              width: 52,
                              height: 2,
                              decoration: BoxDecoration(
                                color: AppColors.brand.withOpacity(0.65),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            SizedBox(height: 18),
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.brand,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
