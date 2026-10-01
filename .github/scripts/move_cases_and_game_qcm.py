from pathlib import Path
import re

ROOT = Path('source/lib/screens')


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def write(name, text):
    (ROOT / name).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'{label}: bloc introuvable')
    return text.replace(old, new, 1)

# -----------------------------------------------------------------------------
# 1) Accueil : retirer complètement les cas cliniques du fil.
# -----------------------------------------------------------------------------
home = read('home_screen.dart')
home = replace_once(home, "import 'clinical_cases_section.dart';\n", '', 'home import clinical cases')
home = replace_once(home, "  final GlobalKey _clinicalCasesFeedKey = GlobalKey();\n", '', 'home clinical key')
home = replace_once(home, "                    clinicalCasesFeedKey: _clinicalCasesFeedKey,\n", '', 'home dashboard clinical arg')
home = replace_once(home, "  final GlobalKey clinicalCasesFeedKey;\n", '', 'dashboard clinical field')
home = replace_once(home, "    required this.clinicalCasesFeedKey,\n", '', 'dashboard clinical ctor')

pattern = re.compile(
    r"          Center\(\n            child: Wrap\(.*?\n          SizedBox\(height: 14\),\n          DailyNewsSection\(verticalFeedKey: newsFeedKey\),\n          SizedBox\(height: 18\),\n          ClinicalCasesSection\(verticalFeedKey: clinicalCasesFeedKey\),",
    re.S,
)
replacement = """          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  final targetContext = newsFeedKey.currentContext;
                  if (targetContext == null) return;
                  Scrollable.ensureVisible(
                    targetContext,
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    alignment: 0.04,
                  );
                },
                child: Ink(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.brandBright, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Actualités plus bas',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.brandBright,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          DailyNewsSection(verticalFeedKey: newsFeedKey),"""
home, count = pattern.subn(replacement, home, count=1)
if count != 1:
    raise SystemExit(f'home feed replacement: {count}')
write('home_screen.dart', home)

# -----------------------------------------------------------------------------
# 2) Écran dédié aux cas cliniques, dans l'univers Practice.
# -----------------------------------------------------------------------------
clinical_screen = """import 'package:flutter/material.dart';

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
"""
write('clinical_cases_screen.dart', clinical_screen)

# -----------------------------------------------------------------------------
# 3) Practice : bouton dédié pour accéder aux cas cliniques.
# -----------------------------------------------------------------------------
practice = read('practice_screen.dart')
practice = replace_once(
    practice,
    "import 'practice_qcm_screen.dart';\n",
    "import 'practice_qcm_screen.dart';\nimport 'clinical_cases_screen.dart';\n",
    'practice import clinical screen',
)
practice = replace_once(
    practice,
    """              const SizedBox(height: 22),
              _sectionLabel('DÉFIS QCM'),
""",
    """              const SizedBox(height: 22),
              _sectionLabel('CAS CLINIQUES'),
              const SizedBox(height: 10),
              _ClinicalCasesGameCard(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ClinicalCasesScreen()),
                ),
              ),
              const SizedBox(height: 22),
              _sectionLabel('DÉFIS QCM'),
""",
    'practice clinical cases button',
)

marker = "\nclass _QcmPracticeCard extends StatelessWidget {\n"
if marker not in practice:
    raise SystemExit('practice qcm class marker missing')
clinical_card = r'''
class _ClinicalCasesGameCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ClinicalCasesGameCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PracticeColors.gamePurple.withOpacity(.34),
                PracticeColors.surface,
                PracticeColors.gameBlue.withOpacity(.20),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: PracticeColors.gamePurple.withOpacity(.48),
            ),
            boxShadow: [
              BoxShadow(
                color: PracticeColors.gamePurple.withOpacity(.15),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -8,
                top: -20,
                child: Icon(
                  Icons.psychology_alt_rounded,
                  size: 92,
                  color: Colors.white.withOpacity(.055),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          PracticeColors.gamePurple.withOpacity(.42),
                          PracticeColors.gameBlue.withOpacity(.28),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: PracticeColors.gameGold.withOpacity(.28),
                      ),
                    ),
                    child: const Icon(
                      Icons.medical_information_rounded,
                      color: PracticeColors.gameGold,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'CAS CLINIQUES',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .35,
                              ),
                            ),
                            SizedBox(width: 7),
                            Icon(
                              Icons.auto_awesome_rounded,
                              color: PracticeColors.gameGold,
                              size: 15,
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Ouvrir les dossiers anonymisés et leurs défis QCM',
                          style: TextStyle(
                            color: PracticeColors.textSecondary,
                            fontSize: 10.8,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
'''
practice = practice.replace(marker, '\n' + clinical_card + marker, 1)
write('practice_screen.dart', practice)

# -----------------------------------------------------------------------------
# 4) Écran QCM statistiques/classement : même identité gaming que Practice.
# -----------------------------------------------------------------------------
qcm = read('practice_qcm_screen.dart')
qcm = replace_once(
    qcm,
    """  static const _bg = Color(0xFF062E20);
  static const _surface = Color(0xFF0B4933);
  static const _elevated = Color(0xFF116044);
  static const _accent = Color(0xFF20D67A);
  static const _secondary = Color(0xFFB8D6C9);
  static const _line = Color(0xFF287154);
""",
    """  static const _bg = Color(0xFF071526);
  static const _surface = Color(0xFF10243A);
  static const _elevated = Color(0xFF17314E);
  static const _accent = Color(0xFF5BE7B0);
  static const _purple = Color(0xFF8B6CFF);
  static const _blue = Color(0xFF3295FF);
  static const _gold = Color(0xFFFFD166);
  static const _pink = Color(0xFFFF6FAE);
  static const _secondary = Color(0xFFB9CBE0);
  static const _line = Color(0xFF244B68);
""",
    'qcm palette',
)

old_header = """            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_surface, _elevated],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _accent.withOpacity(.22)),
                    ),
                    child: const Icon(Icons.quiz_rounded, color: _accent, size: 25),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vos statistiques QCM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.35,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Votre progression sur les cas cliniques du fil d’accueil.',
                          style: TextStyle(
                            color: _secondary,
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
"""
new_header = """            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 16, 17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6B50E8), Color(0xFF226FC6), Color(0xFF0B8F76)],
                  stops: [0, .55, 1],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withOpacity(.25),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -14,
                    top: -24,
                    child: Icon(
                      Icons.quiz_rounded,
                      size: 108,
                      color: Colors.white.withOpacity(.09),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.13),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: _gold.withOpacity(.34)),
                        ),
                        child: const Icon(Icons.sports_esports_rounded, color: _gold, size: 27),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QCM ARENA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .45,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Scores, précision et classement des défis Practice',
                              style: TextStyle(
                                color: Color(0xFFE9F2FF),
                                fontSize: 11.2,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.bolt_rounded, color: _gold, size: 27),
                    ],
                  ),
                ],
              ),
            ),
"""
qcm = replace_once(qcm, old_header, new_header, 'qcm arena header')

qcm = replace_once(
    qcm,
    """                color: _surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _line),
""",
    """                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_purple.withOpacity(.24), _surface, _blue.withOpacity(.12)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _purple.withOpacity(.38)),
""",
    'qcm rank card decoration',
)
qcm = replace_once(qcm, "const Icon(Icons.emoji_events_rounded, color: _accent)", "const Icon(Icons.emoji_events_rounded, color: _gold)", 'qcm rank icon')
qcm = replace_once(qcm, "const Text('Classement QCM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))", "const Row(children: [Icon(Icons.leaderboard_rounded, color: _gold, size: 20), SizedBox(width: 8), Text('LEADERBOARD QCM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: .25))])", 'qcm leaderboard title')

# metric tiles
qcm = replace_once(
    qcm,
    """      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _PracticeQcmScreenState._surface,
          _PracticeQcmScreenState._elevated,
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _PracticeQcmScreenState._line),
""",
    """      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _PracticeQcmScreenState._purple.withOpacity(.26),
          _PracticeQcmScreenState._surface,
          _PracticeQcmScreenState._blue.withOpacity(.15),
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _PracticeQcmScreenState._purple.withOpacity(.34)),
      boxShadow: [
        BoxShadow(
          color: _PracticeQcmScreenState._purple.withOpacity(.10),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
""",
    'qcm metric gaming',
)

# selected segment colors
qcm = qcm.replace(
    "? _PracticeQcmScreenState._elevated\n        : _PracticeQcmScreenState._surface",
    "? _PracticeQcmScreenState._purple.withOpacity(.30)\n        : _PracticeQcmScreenState._surface",
)
qcm = qcm.replace(
    "? _PracticeQcmScreenState._accent\n                : _PracticeQcmScreenState._line",
    "? _PracticeQcmScreenState._purple\n                : _PracticeQcmScreenState._line",
)
qcm = qcm.replace(
    "_PracticeQcmScreenState._accent.withOpacity(.07)",
    "_PracticeQcmScreenState._purple.withOpacity(.16)",
)

# leaderboard rows
qcm = replace_once(
    qcm,
    """        color: _PracticeQcmScreenState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: entry.rank <= 3
              ? _PracticeQcmScreenState._accent.withOpacity(.40)
              : _PracticeQcmScreenState._line,
        ),
""",
    """        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            entry.rank <= 3
                ? _PracticeQcmScreenState._gold.withOpacity(.13)
                : _PracticeQcmScreenState._purple.withOpacity(.10),
            _PracticeQcmScreenState._surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: entry.rank <= 3
              ? _PracticeQcmScreenState._gold.withOpacity(.42)
              : _PracticeQcmScreenState._purple.withOpacity(.22),
        ),
""",
    'qcm leaderboard gaming row',
)
write('practice_qcm_screen.dart', qcm)

# -----------------------------------------------------------------------------
# 5) QCM dans les cas : questions, propositions et explications IA plus gaming.
#    Toute la logique de réponse/correction/parsing reste inchangée.
# -----------------------------------------------------------------------------
cases = read('clinical_cases_section.dart')

cases = cases.replace(
    "import '../theme/screen_decor.dart';\n",
    "import '../theme/screen_decor.dart';\n\nabstract final class _CaseGameColors {\n  static const bg = Color(0xFF071526);\n  static const surface = Color(0xFF10243A);\n  static const elevated = Color(0xFF17314E);\n  static const purple = Color(0xFF8B6CFF);\n  static const blue = Color(0xFF3295FF);\n  static const gold = Color(0xFFFFD166);\n  static const pink = Color(0xFFFF6FAE);\n  static const mint = Color(0xFF5BE7B0);\n  static const text = Color(0xFFF5F8FF);\n  static const secondary = Color(0xFFB9CBE0);\n  static const line = Color(0xFF244B68);\n}\n",
    1,
)

# top banner
cases = replace_once(
    cases,
    """          DecorSectionBanner(
            scene: ScreenDecorScene.practice,
            title: 'CAS CLINIQUES',
            subtitle: 'Dossiers anonymisés · raisonnement clinique · 5 QCM par cas',
            icon: Icons.medical_information_rounded,
            trailing: DecorIconAction(
              icon: Icons.refresh_rounded,
              tooltip: 'Actualiser',
              onTap: _loading ? null : () => _load(reset: true),
            ),
          ),
""",
    """          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6B50E8), Color(0xFF226FC6), Color(0xFF0B8F76)],
                stops: [0, .55, 1],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                  color: _CaseGameColors.purple.withOpacity(.22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.13),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _CaseGameColors.gold.withOpacity(.34)),
                  ),
                  child: const Icon(Icons.medical_information_rounded, color: _CaseGameColors.gold, size: 25),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CLINICAL ARENA', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: .55)),
                      SizedBox(height: 3),
                      Text('Dossiers anonymisés · raisonnement · 5 défis QCM par cas', style: TextStyle(color: Color(0xFFE9F2FF), fontSize: 10.5, height: 1.35, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser',
                  onPressed: _loading ? null : () => _load(reset: true),
                  icon: const Icon(Icons.refresh_rounded),
                  color: Colors.white,
                ),
              ],
            ),
          ),
""",
    'cases gaming banner',
)

# outer case card
cases = replace_once(
    cases,
    """        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.card, AppColors.brandSoft.withOpacity(.38)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.brand.withOpacity(.30)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.13),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
""",
    """        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _CaseGameColors.purple.withOpacity(.24),
            _CaseGameColors.surface,
            _CaseGameColors.blue.withOpacity(.12),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _CaseGameColors.purple.withOpacity(.34)),
        boxShadow: [
          BoxShadow(
            color: _CaseGameColors.purple.withOpacity(.14),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
""",
    'case outer gaming',
)
# header labels visible on dark card
cases = cases.replace("color: AppColors.inkSoft,\n                    fontSize: 11,", "color: _CaseGameColors.secondary,\n                    fontSize: 11,", 1)
cases = cases.replace("color: AppColors.paperAlt,\n                  borderRadius: BorderRadius.circular(999),", "color: Colors.white.withOpacity(.08),\n                  borderRadius: BorderRadius.circular(999),", 1)
cases = cases.replace("border: Border.all(color: AppColors.line),", "border: Border.all(color: Colors.white.withOpacity(.12)),", 1)

# QCM challenge container
old_qcm_box = """              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.brandSoft.withOpacity(.72),
                    AppColors.card,
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.brand.withOpacity(.34)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withOpacity(.09),
                    blurRadius: 16,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
"""
new_qcm_box = """              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _CaseGameColors.purple.withOpacity(.34),
                    _CaseGameColors.elevated,
                    _CaseGameColors.blue.withOpacity(.18),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _CaseGameColors.purple.withOpacity(.52)),
                boxShadow: [
                  BoxShadow(
                    color: _CaseGameColors.purple.withOpacity(.18),
                    blurRadius: 22,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
"""
cases = replace_once(cases, old_qcm_box, new_qcm_box, 'case qcm box')
cases = cases.replace("Icons.quiz_rounded,\n                        color: AppColors.brandBright,", "Icons.sports_esports_rounded,\n                        color: _CaseGameColors.gold,", 1)
cases = cases.replace("'QCM ${_currentQcm + 1} / ${_qcms.length}'", "'DÉFI ${_currentQcm + 1} / ${_qcms.length}'", 1)
cases = cases.replace("color: AppColors.brandBright,\n                          fontSize: 10,", "color: _CaseGameColors.gold,\n                          fontSize: 10,", 1)

# Question: insert a dedicated glass card around the exact Text widget.
old_question = """                  const SizedBox(height: 8),
                  Text(
                    current.question,
                    style: TextStyle(
                      color: AppColors.ink,
                      fontSize: 14.5,
                      height: 1.42,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.08,
                    ),
                  ),
                  const SizedBox(height: 11),
"""
new_question = """                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.13),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(.10)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _CaseGameColors.gold.withOpacity(.14),
                            shape: BoxShape.circle,
                            border: Border.all(color: _CaseGameColors.gold.withOpacity(.26)),
                          ),
                          child: const Icon(Icons.bolt_rounded, color: _CaseGameColors.gold, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            current.question,
                            style: const TextStyle(
                              color: _CaseGameColors.text,
                              fontSize: 15.2,
                              height: 1.43,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
"""
cases = replace_once(cases, old_question, new_question, 'question visual')

# Explanation result panel
old_expl = """              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: (correct ? AppColors.success : AppColors.danger)
                      .withOpacity(0.09),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (correct ? AppColors.success : AppColors.danger)
                        .withOpacity(0.45),
                  ),
                ),
"""
new_expl = """              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      (correct ? AppColors.success : AppColors.danger).withOpacity(.19),
                      _CaseGameColors.surface,
                      _CaseGameColors.purple.withOpacity(.16),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: (correct ? AppColors.success : AppColors.danger).withOpacity(0.55),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _CaseGameColors.purple.withOpacity(.10),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
"""
cases = replace_once(cases, old_expl, new_expl, 'explanation gaming panel')
cases = cases.replace("'EXPLICATION + SOURCES'", "'EXPLICATION IA + SOURCES'", 1)
cases = cases.replace("color: AppColors.brandBright,\n                          size: 15,", "color: _CaseGameColors.gold,\n                          size: 15,", 1)
cases = cases.replace("color: AppColors.brandBright,\n                            fontSize: 9,", "color: _CaseGameColors.gold,\n                            fontSize: 9,", 1)

# Guideline explanation text into a dedicated AI glass card.
old_guideline_text = """        Text(
          explanation,
          style: TextStyle(
            color: AppColors.inkSoft,
            fontSize: 11.5,
            height: 1.46,
            fontWeight: FontWeight.w600,
          ),
        ),
"""
new_guideline_text = """        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.055),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _CaseGameColors.purple.withOpacity(.20)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _CaseGameColors.purple.withOpacity(.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.psychology_alt_rounded, color: _CaseGameColors.gold, size: 17),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  explanation,
                  style: const TextStyle(
                    color: _CaseGameColors.text,
                    fontSize: 11.8,
                    height: 1.48,
                    fontWeight: FontWeight.w650,
                  ),
                ),
              ),
            ],
          ),
        ),
"""
cases = replace_once(cases, old_guideline_text, new_guideline_text, 'ai explanation glass')

# Source heading and cards on dark background.
cases = cases.replace("color: AppColors.brandBright,\n                size: 15,", "color: _CaseGameColors.gold,\n                size: 15,", 1)
cases = cases.replace("color: AppColors.brandBright,\n                  fontSize: 9,", "color: _CaseGameColors.gold,\n                  fontSize: 9,", 1)
cases = cases.replace("color: AppColors.paperAlt,\n                    borderRadius: BorderRadius.circular(12),\n                    border: Border.all(color: AppColors.line.withOpacity(.75)),", "color: Colors.white.withOpacity(.055),\n                    borderRadius: BorderRadius.circular(12),\n                    border: Border.all(color: _CaseGameColors.line.withOpacity(.90)),", 1)
cases = cases.replace("color: AppColors.brandBright,\n                                fontSize: 9.5,", "color: _CaseGameColors.gold,\n                                fontSize: 9.5,", 1)
cases = cases.replace("color: AppColors.inkSoft,\n                                fontSize: 10.5,", "color: _CaseGameColors.secondary,\n                                fontSize: 10.5,", 1)
cases = cases.replace("color: AppColors.inkFaint,", "color: _CaseGameColors.secondary,", 1)

# QCM options: dark gaming cards, stronger states, clearer letters.
old_option_colors = """    Color border = AppColors.line;
    Color background = AppColors.card;
    Color foreground = AppColors.ink;
"""
new_option_colors = """    Color border = _CaseGameColors.line;
    Color background = _CaseGameColors.surface;
    Color foreground = _CaseGameColors.text;
"""
cases = replace_once(cases, old_option_colors, new_option_colors, 'option base colors')
cases = cases.replace("border = AppColors.brand;\n      background = AppColors.brandSoft;", "border = _CaseGameColors.purple;\n      background = _CaseGameColors.purple.withOpacity(.20);", 1)
cases = cases.replace("borderRadius: BorderRadius.circular(18),\n        child: AnimatedContainer", "borderRadius: BorderRadius.circular(19),\n        child: AnimatedContainer", 1)
cases = cases.replace("padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),", "padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),", 1)
cases = cases.replace("borderRadius: BorderRadius.circular(18),\n            border: Border.all(", "borderRadius: BorderRadius.circular(19),\n            border: Border.all(", 1)
cases = cases.replace("width: 34,\n                height: 34,", "width: 38,\n                height: 38,", 1)
cases = cases.replace("borderRadius: BorderRadius.circular(10),", "borderRadius: BorderRadius.circular(12),", 1)
cases = cases.replace("fontSize: 11,\n                    fontWeight: FontWeight.w900,", "fontSize: 12,\n                    fontWeight: FontWeight.w900,", 1)
cases = cases.replace("fontSize: 11.8,\n                      height: 1.42,", "fontSize: 12.3,\n                      height: 1.43,", 1)

# progress dots: current = purple rather than app brand.
cases = cases.replace("? AppColors.brandBright\n                                : AppColors.line", "? _CaseGameColors.purple\n                                : _CaseGameColors.line", 1)

# Footer privacy on dark screen.
cases = cases.replace("color: AppColors.paperAlt,\n              borderRadius: BorderRadius.circular(14),\n              border: Border.all(color: AppColors.line),", "color: Colors.white.withOpacity(.055),\n              borderRadius: BorderRadius.circular(14),\n              border: Border.all(color: _CaseGameColors.line),", 1)
cases = cases.replace("Icon(Icons.shield_outlined, size: 17, color: AppColors.inkSoft)", "const Icon(Icons.shield_outlined, size: 17, color: _CaseGameColors.mint)", 1)
cases = cases.replace("color: AppColors.inkSoft,\n                      fontSize: 10.5,", "color: _CaseGameColors.secondary,\n                      fontSize: 10.5,", 1)

write('clinical_cases_section.dart', cases)

print('Patch Practice/cas/QCM appliqué avec succès.')
