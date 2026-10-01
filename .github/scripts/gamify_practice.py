from pathlib import Path

practice = Path('source/lib/screens/practice_screen.dart')
text = practice.read_text(encoding='utf-8')

def replace_once(old: str, new: str, label: str):
    global text
    if old not in text:
        raise SystemExit(f'{label}: bloc introuvable')
    text = text.replace(old, new, 1)

# Palette Practice : médical + gaming, sans toucher aux données ni callbacks.
replace_once(
"""abstract final class PracticeColors {
  static const background = Color(0xFF071F18);
  static const surface = Color(0xFF0E3025);
  static const elevated = Color(0xFF14392C);
  static const accent = Color(0xFF22D985);
  static const text = Color(0xFFF4F8F6);
  static const textSecondary = Color(0xFFB6CAC0);
  static const line = Color(0xFF1B4A38);
""",
"""abstract final class PracticeColors {
  static const background = Color(0xFF071526);
  static const surface = Color(0xFF10243A);
  static const elevated = Color(0xFF17314E);
  static const accent = Color(0xFF5BE7B0);
  static const gamePurple = Color(0xFF8B6CFF);
  static const gameBlue = Color(0xFF3295FF);
  static const gameGold = Color(0xFFFFD166);
  static const gamePink = Color(0xFFFF6FAE);
  static const text = Color(0xFFF5F8FF);
  static const textSecondary = Color(0xFFB9CBE0);
  static const line = Color(0xFF244B68);
""",
'palette',
)

# Header gamifié sur l'écran Practice principal.
replace_once(
"""              const SizedBox(height: 20),
              _sectionLabel('GARDE EN COURS'),
""",
"""              const SizedBox(height: 20),
              _PracticeGameHeader(
                level: level,
                xp: _all.xp,
                streak: _all.streak,
                unlocked: unlocked,
              ),
              const SizedBox(height: 22),
              _sectionLabel('MISSION EN COURS'),
""",
'header insertion',
)

for old, new in [
    ("_sectionLabel('VUE D’ENSEMBLE')", "_sectionLabel('STATS DE PARTIE')"),
    ("_sectionLabel('APPRENTISSAGE QCM')", "_sectionLabel('DÉFIS QCM')"),
    ("_sectionLabel('PROGRESSION')", "_sectionLabel('LEADERBOARD & SUCCÈS')"),
    ("_sectionLabel('PRÉFÉRENCES')", "_sectionLabel('RÉGLAGES DU PROFIL')"),
]:
    replace_once(old, new, old)

# Carte QCM : aspect défi/mission.
replace_once(
"""          decoration: BoxDecoration(
            color: PracticeColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: PracticeColors.line),
          ),
""",
"""          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                PracticeColors.gamePurple.withOpacity(.30),
                PracticeColors.surface,
                PracticeColors.gameBlue.withOpacity(.16),
              ],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: PracticeColors.gamePurple.withOpacity(.44),
            ),
            boxShadow: [
              BoxShadow(
                color: PracticeColors.gamePurple.withOpacity(.16),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
""",
'qcm decoration',
)
replace_once(
"""                        Text(
                          'QCM des cas cliniques',
""",
"""                        Text(
                          'Défi QCM · cas cliniques',
""",
'qcm title',
)

# Carte Practice de l'accueil : fond ludique / arcade premium.
replace_once(
"""        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.11),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(.20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
""",
"""        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6E56E8),
              Color(0xFF247FD5),
              Color(0xFF13A982),
            ],
            stops: [0, .54, 1],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(.28)),
          boxShadow: [
            BoxShadow(
              color: PracticeColors.gamePurple.withOpacity(.30),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: PracticeColors.gameBlue.withOpacity(.12),
              blurRadius: 42,
              spreadRadius: 2,
            ),
          ],
        ),
""",
'home card decoration',
)
replace_once(
"""                    color: PracticeColors.accent.withOpacity(.18),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: PracticeColors.accent.withOpacity(.32),
                    ),
                  ),
                  child: const Icon(
                    Icons.medical_information_rounded,
                    color: PracticeColors.accent,
                    size: 21,
""",
"""                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        PracticeColors.gameGold.withOpacity(.30),
                        Colors.white.withOpacity(.12),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: PracticeColors.gameGold.withOpacity(.60),
                    ),
                  ),
                  child: const Icon(
                    Icons.sports_esports_rounded,
                    color: PracticeColors.gameGold,
                    size: 22,
""",
'home game icon',
)
replace_once(
"""                        'Suivi de garde · patients documentés',
""",
"""                        'MODE JEU · progression clinique',
""",
'home subtitle',
)
replace_once(
"""                          color: PracticeColors.accent,
                          size: 17,
""",
"""                          color: PracticeColors.gameGold,
                          size: 17,
""",
'home trophy color',
)
replace_once(
"""        Icon(icon, color: PracticeColors.accent, size: 12),
""",
"""        Icon(icon, color: PracticeColors.gameGold, size: 12),
""",
'home chip icons',
)

# Mission active plus jeu.
replace_once(
"""      decoration: BoxDecoration(
        color: PracticeColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PracticeColors.line),
      ),
""",
"""      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            PracticeColors.gameBlue.withOpacity(.24),
            PracticeColors.surface,
            PracticeColors.gamePurple.withOpacity(.13),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: PracticeColors.gameBlue.withOpacity(.38)),
        boxShadow: [
          BoxShadow(
            color: PracticeColors.gameBlue.withOpacity(.10),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
""",
'current mission card',
)
replace_once("'EN COURS'", "'MISSION ACTIVE'", 'mission label')

# Niveau = carte XP plus gaming.
replace_once(
"""    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: PracticeColors.line),
    ),
""",
"""    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeColors.gamePurple.withOpacity(.26),
          PracticeColors.surface,
          PracticeColors.gameBlue.withOpacity(.12),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: PracticeColors.gamePurple.withOpacity(.40)),
      boxShadow: [
        BoxShadow(
          color: PracticeColors.gamePurple.withOpacity(.11),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
""",
'level card',
)
replace_once(
"""            color: PracticeColors.accent,
            backgroundColor: PracticeColors.background,
""",
"""            color: PracticeColors.gameGold,
            backgroundColor: PracticeColors.background,
""",
'level progress',
)

# Les cartes de statistiques deviennent des tuiles de score.
replace_once(
"""    decoration: BoxDecoration(
      color: PracticeColors.surface,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: PracticeColors.line),
    ),
""",
"""    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeColors.gameBlue.withOpacity(.18),
          PracticeColors.surface,
        ],
      ),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: PracticeColors.gameBlue.withOpacity(.28)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.10),
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    ),
""",
'stat card',
)

# Actions progression : cartes façon menu de jeu.
replace_once(
"""        decoration: BoxDecoration(
          color: PracticeColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PracticeColors.line),
        ),
""",
"""        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              PracticeColors.gamePurple.withOpacity(.15),
              PracticeColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: PracticeColors.gamePurple.withOpacity(.24)),
        ),
""",
'action tile',
)

# Ajout du header Practice Arena (présentation des données déjà calculées).
marker = "\nclass _QcmPracticeCard extends StatelessWidget {\n"
if marker not in text:
    raise SystemExit('marker QCM introuvable')
header_class = r'''
class _PracticeGameHeader extends StatelessWidget {
  final PracticeLevel level;
  final int xp;
  final int streak;
  final int unlocked;

  const _PracticeGameHeader({
    required this.level,
    required this.xp,
    required this.streak,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6B50E8), Color(0xFF226FC6), Color(0xFF0B8F76)],
          stops: [0, .55, 1],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(.18)),
        boxShadow: [
          BoxShadow(
            color: PracticeColors.gamePurple.withOpacity(.24),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -18,
            child: Icon(
              Icons.sports_esports_rounded,
              size: 104,
              color: Colors.white.withOpacity(.10),
            ),
          ),
          Positioned(
            right: 72,
            bottom: -12,
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 42,
              color: PracticeColors.gameGold.withOpacity(.20),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.14),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white.withOpacity(.18)),
                    ),
                    child: const Icon(
                      Icons.sports_esports_rounded,
                      color: PracticeColors.gameGold,
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PRACTICE ARENA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Documente · apprends · gagne de l’XP',
                          style: TextStyle(
                            color: Color(0xFFE9F2FF),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.bolt_rounded,
                    color: PracticeColors.gameGold,
                    size: 25,
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _PracticeGameBadge(
                    icon: Icons.military_tech_rounded,
                    label: 'Niveau ${level.number}',
                    color: PracticeColors.gameGold,
                  ),
                  _PracticeGameBadge(
                    icon: Icons.bolt_rounded,
                    label: '$xp XP',
                    color: PracticeColors.accent,
                  ),
                  _PracticeGameBadge(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Série $streak',
                    color: PracticeColors.gamePink,
                  ),
                  _PracticeGameBadge(
                    icon: Icons.workspace_premium_rounded,
                    label: '$unlocked succès',
                    color: Colors.white,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PracticeGameBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _PracticeGameBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(.34)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}
'''
text = text.replace(marker, '\n' + header_class + marker, 1)
practice.write_text(text, encoding='utf-8')

# Le décor partagé Practice devient réellement gaming sur tous les sous-écrans Practice.
decor = Path('source/lib/theme/screen_decor.dart')
d = decor.read_text(encoding='utf-8')

def dreplace(old: str, new: str, label: str):
    global d
    if old not in d:
        raise SystemExit(f'decor {label}: bloc introuvable')
    d = d.replace(old, new, 1)

dreplace(
"""      case ScreenDecorScene.practice:
        return AppColors.cyan;
""",
"""      case ScreenDecorScene.practice:
        return const Color(0xFF8B6CFF);
""",
'accent',
)
dreplace(
"""      case ScreenDecorScene.practice:
        return Icons.medical_services_rounded;
""",
"""      case ScreenDecorScene.practice:
        return Icons.sports_esports_rounded;
""",
'primary icon',
)
dreplace(
"""      case ScreenDecorScene.practice:
        return Icons.medical_information_rounded;
""",
"""      case ScreenDecorScene.practice:
        return Icons.emoji_events_rounded;
""",
'secondary icon',
)

dreplace(
"""                colors: [
                  accent.withOpacity(dark ? .13 : .09),
                  Colors.transparent,
                  accent.withOpacity(dark ? .055 : .035),
                ],
                stops: const [0, .52, 1],
""",
"""                colors: scene == ScreenDecorScene.practice
                    ? [
                        const Color(0xFF8B6CFF).withOpacity(dark ? .20 : .14),
                        const Color(0xFF3295FF).withOpacity(dark ? .08 : .055),
                        const Color(0xFF22D985).withOpacity(dark ? .10 : .06),
                      ]
                    : [
                        accent.withOpacity(dark ? .13 : .09),
                        Colors.transparent,
                        accent.withOpacity(dark ? .055 : .035),
                      ],
                stops: const [0, .52, 1],
""",
'gradient',
)

# Plus de petits symboles de jeu, uniquement sur scene Practice.
dreplace(
"""              Positioned(
                bottom: -72,
                right: -52,
                child: _GlowOrb(
                  size: 210,
                  color: accent.withOpacity(dark ? .08 : .055),
                ),
              ),
              if (scene.showLogo)
""",
"""              Positioned(
                bottom: -72,
                right: -52,
                child: _GlowOrb(
                  size: 210,
                  color: accent.withOpacity(dark ? .08 : .055),
                ),
              ),
              if (scene == ScreenDecorScene.practice) ...[
                Positioned(
                  top: 172,
                  right: 18,
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 38,
                    color: const Color(0xFFFFD166).withOpacity(.10),
                  ),
                ),
                Positioned(
                  bottom: 178,
                  right: 26,
                  child: Icon(
                    Icons.bolt_rounded,
                    size: 48,
                    color: const Color(0xFF5BE7B0).withOpacity(.08),
                  ),
                ),
                Positioned(
                  bottom: 280,
                  left: 18,
                  child: Icon(
                    Icons.workspace_premium_rounded,
                    size: 44,
                    color: const Color(0xFFFF6FAE).withOpacity(.07),
                  ),
                ),
              ],
              if (scene.showLogo)
""",
'practice game symbols',
)

decor.write_text(d, encoding='utf-8')
