import 'package:flutter/material.dart';

import '../theme/screen_decor.dart';
import 'clinical_cases_section.dart';

class ClinicalCasesScreen extends StatelessWidget {
  const ClinicalCasesScreen({super.key});

  static const _background = Color(0xFF071526);
  static const _purple = Color(0xFF8B6CFF);
  static const _gold = Color(0xFFFFD166);

  @override
  Widget build(BuildContext context) {
    return DecorScaffold(
      scene: ScreenDecorScene.practice,
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 6,
        title: const Row(
          children: [
            Icon(Icons.sports_esports_rounded, color: _gold, size: 22),
            SizedBox(width: 9),
            Text(
              'Cas cliniques · Practice',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.2),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: const ClinicalCasesSection(),
      ),
    );
  }
}
