from pathlib import Path


def replace_between(text: str, start_marker: str, end_marker: str, replacement: str, *, start_at: int = 0):
    start = text.index(start_marker, start_at)
    end = text.index(end_marker, start)
    return text[:start] + replacement + text[end:], start


practice_path = Path('source/lib/screens/practice_screen.dart')
practice = practice_path.read_text(encoding='utf-8')

# 1) Home feed Practice summary: same data/actions, much more visible presentation.
class_start = practice.index('class _PracticeHomeSummaryState')
build_start = practice.index('  @override\n  Widget build(BuildContext context) {', class_start)
build_end_marker = '\n  }\n}\n\nclass _CurrentGuardCard'
build_end = practice.index(build_end_marker, build_start) + len('\n  }')
new_home_build = r'''  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 6);
    final guard = _guard;
    final showRank = _ranks.leaderboardOptIn;
    if (guard == null && !showRank) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: PracticeColors.accent.withOpacity(.18),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(
                      color: PracticeColors.accent.withOpacity(.32),
                    ),
                  ),
                  child: const Icon(
                    Icons.medical_information_rounded,
                    color: PracticeColors.accent,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRACTICE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Suivi de garde · patients documentés',
                        style: TextStyle(
                          color: Color(0xFFDCEBE4),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (guard != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: PracticeColors.accent.withOpacity(.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: PracticeColors.accent.withOpacity(.28),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          color: PracticeColors.accent,
                          size: 7,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'GARDE ACTIVE',
                          style: TextStyle(
                            color: PracticeColors.accent,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .45,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (guard != null) ...[
              const SizedBox(height: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PracticeGuardScreen(
                        appState: widget.appState,
                        guard: guard,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(.14)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.description_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _stats.patients == 0
                                    ? 'Votre garde vient de commencer'
                                    : '${_stats.patients} patient${_stats.patients > 1 ? 's' : ''} documenté${_stats.patients > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${guard.title} · ${guard.timeLabel}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(.76),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _homeStatChip(
                                    Icons.people_alt_outlined,
                                    '${_stats.patients} vus',
                                  ),
                                  _homeStatChip(
                                    Icons.hourglass_bottom_rounded,
                                    '${_stats.waiting} attente',
                                  ),
                                  _homeStatChip(
                                    Icons.logout_rounded,
                                    '${_stats.discharged} sortants',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withOpacity(.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (showRank) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PracticeLeaderboardScreen(
                        appState: widget.appState,
                      ),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.055),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events_outlined,
                          color: PracticeColors.accent,
                          size: 17,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _ranks.hasActivity
                                ? 'Classement : ${_ranks.promotionRank == null ? '—' : '${_ranks.promotionRank}e'} promo · ${_ranks.globalRank == null ? '—' : '${_ranks.globalRank}e'} global'
                                : 'Classement disponible après votre première activité Practice.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(.90),
                              fontSize: 10.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(.66),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _homeStatChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(.12),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Colors.white.withOpacity(.10)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: PracticeColors.accent, size: 12),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );'''
practice = practice[:build_start] + new_home_build + practice[build_end:]

# 2) Patient form chapter banners: visual only.
chapter_start = practice.index('  Widget _formChapterTitle(')
chapter_end = practice.index('  IconData _formSectionIcon', chapter_start)
new_chapter = r'''  Widget _formChapterTitle(String title, IconData icon, String subtitle) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(0, 14, 0, 11),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              PracticeColors.accent.withOpacity(.16),
              PracticeColors.elevated.withOpacity(.52),
            ],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: PracticeColors.accent.withOpacity(.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: PracticeColors.accent.withOpacity(.16),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: PracticeColors.accent.withOpacity(.24),
                ),
              ),
              child: Icon(icon, color: PracticeColors.accent, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: PracticeColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .85,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: PracticeColors.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

'''
practice = practice[:chapter_start] + new_chapter + practice[chapter_end:]

section_start = practice.index('  Widget _formSection({')
section_end = practice.index('  Widget _clinicalSection(', section_start)
new_section = r'''  Widget _formSection({
    required String title,
    required List<Widget> children,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          PracticeColors.surface,
          PracticeColors.elevated.withOpacity(.86),
        ],
      ),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: PracticeColors.accent.withOpacity(.20)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.16),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: PracticeColors.accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 9),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PracticeColors.accent.withOpacity(.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _formSectionIcon(title),
                color: PracticeColors.accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: PracticeColors.text,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .72,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

'''
practice = practice[:section_start] + new_section + practice[section_end:]
practice_path.write_text(practice, encoding='utf-8')


clinical_path = Path('source/lib/screens/clinical_cases_section.dart')
clinical = clinical_path.read_text(encoding='utf-8')

# 3) Highly visible clinical feed banner, same refresh action.
state_start = clinical.index('class _ClinicalCasesSectionState')
build_start = clinical.index('  Widget build(BuildContext context) {', state_start)
header_start = clinical.index('          Row(\n', build_start)
header_end = clinical.index('          const SizedBox(height: 12),', header_start)
new_header = r'''          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(15, 15, 11, 15),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.brandDark, AppColors.brand],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withOpacity(.20),
                  blurRadius: 22,
                  offset: const Offset(0, 9),
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
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.18)),
                  ),
                  child: const Icon(
                    Icons.clinical_notes_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CAS CLINIQUES',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 18.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Dossiers anonymisés · raisonnement clinique · 5 QCM par cas',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.78),
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: _loading ? null : () => _load(reset: true),
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.12),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.white.withOpacity(.16)),
                      ),
                      child: Icon(
                        Icons.refresh_rounded,
                        color: Colors.white.withOpacity(_loading ? .45 : .95),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
'''
clinical = clinical[:header_start] + new_header + clinical[header_end:]

old_case_decoration = r'''      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.brand.withOpacity(.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),'''
new_case_decoration = r'''      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.card,
            AppColors.brandSoft.withOpacity(.38),
          ],
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
      ),'''
assert old_case_decoration in clinical, 'Clinical case card decoration anchor missing'
clinical = clinical.replace(old_case_decoration, new_case_decoration, 1)

old_qcm_decoration = r'''              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: AppColors.paperAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.brand.withOpacity(.18)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withOpacity(.05),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),'''
new_qcm_decoration = r'''              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
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
              ),'''
assert old_qcm_decoration in clinical, 'QCM card decoration anchor missing'
clinical = clinical.replace(old_qcm_decoration, new_qcm_decoration, 1)

old_case_section = r'''      padding: const EdgeInsets.fromLTRB(11, 10, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.paperAlt.withOpacity(.70),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.line.withOpacity(.72)),
      ),'''
new_case_section = r'''      padding: const EdgeInsets.fromLTRB(12, 11, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.card.withOpacity(.90),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.brand.withOpacity(.14)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(.035),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),'''
assert old_case_section in clinical, 'Case section decoration anchor missing'
clinical = clinical.replace(old_case_section, new_case_section, 1)

# Make QCM choices more card-like without touching selection/correction logic.
clinical = clinical.replace(
    'borderRadius: BorderRadius.circular(16),\n        child: AnimatedContainer(',
    'borderRadius: BorderRadius.circular(18),\n        child: AnimatedContainer(',
    1,
)
clinical = clinical.replace(
    'padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),\n          decoration: BoxDecoration(\n            color: background,\n            borderRadius: BorderRadius.circular(16),',
    'padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),\n          decoration: BoxDecoration(\n            color: background,\n            borderRadius: BorderRadius.circular(18),',
    1,
)
clinical = clinical.replace(
    'width: 30,\n                height: 30,',
    'width: 34,\n                height: 34,',
    1,
)

clinical_path.write_text(clinical, encoding='utf-8')
print('Visual refresh applied: Practice home/patient form + clinical feed/QCM.')
