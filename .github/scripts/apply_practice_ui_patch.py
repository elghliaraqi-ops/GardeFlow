from pathlib import Path
import re

path = Path('source/lib/screens/practice_screen.dart')
text = path.read_text(encoding='utf-8')
original = text

# Keep Practice aligned with the global clinical design system without touching
# any service, persistence, navigation or scoring logic.
old_color_signature = 'static const background = Color(0xFF062E20);'
new_color_signature = 'static const background = Color(0xFF071F18);'
if old_color_signature in text:
    text, count = re.subn(
        r'''abstract final class PracticeColors \{.*?\n\}''',
        '''abstract final class PracticeColors {
  static const background = Color(0xFF071F18);
  static const surface = Color(0xFF0E3025);
  static const elevated = Color(0xFF14392C);
  static const accent = Color(0xFF22D985);
  static const text = Color(0xFFF4F8F6);
  static const textSecondary = Color(0xFFB6CAC0);
  static const line = Color(0xFF1B4A38);
  static const waiting = Color(0xFFF2AD45);
  static const specialist = Color(0xFF5AA8FF);
  static const discharged = Color(0xFF2BC878);
  static const hospitalized = Color(0xFFE25A56);
  static const prescription = Color(0xFF35C3D8);
}''',
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise SystemExit('Could not safely replace PracticeColors')
elif new_color_signature not in text:
    raise SystemExit('Unexpected PracticeColors version; refusing unsafe patch')

text = text.replace(
    'padding: const EdgeInsets.fromLTRB(16, 18, 16, 34),',
    'padding: const EdgeInsets.fromLTRB(16, 10, 16, 34),',
    1,
)

intro = """              const Text(
                'Practice',
                style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.8),
              ),
              const SizedBox(height: 4),
              const Text(
                'Gardes, cas documentés et apprentissage en un seul espace.',
                style: TextStyle(color: PracticeColors.textSecondary, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
"""
if intro in text:
    text = text.replace(intro, '', 1)

old_fab = """      floatingActionButton: widget.guard == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _newCase,
              backgroundColor: PracticeColors.accent,
              foregroundColor: PracticeColors.background,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un malade', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
"""
new_fab = """      floatingActionButton: widget.guard == null
          ? null
          : FloatingActionButton(
              onPressed: _newCase,
              tooltip: 'Ajouter un malade',
              backgroundColor: PracticeColors.accent,
              foregroundColor: PracticeColors.background,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
"""
if old_fab in text:
    text = text.replace(old_fab, new_fab, 1)

old_sort = """            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                initialValue: _sort,
                onSelected: (value) => setState(() => _sort = value),
                color: PracticeColors.surface,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'recent', child: Text('Plus récents')),
                  PopupMenuItem(value: 'oldest', child: Text('Plus anciens')),
                  PopupMenuItem(value: 'patient', child: Text('Patient #')),
                  PopupMenuItem(value: 'arrival', child: Text('Heure d’arrivée')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: PracticeColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PracticeColors.line),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded, color: PracticeColors.textSecondary, size: 17),
                      SizedBox(width: 6),
                      Text('Trier', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
"""
new_sort = """            Row(
              children: [
                Expanded(
                  child: Text(
                    'Patients · ${_visible.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  color: PracticeColors.surface,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'recent', child: Text('Plus récents')),
                    PopupMenuItem(value: 'oldest', child: Text('Plus anciens')),
                    PopupMenuItem(value: 'patient', child: Text('Patient #')),
                    PopupMenuItem(value: 'arrival', child: Text('Heure d’arrivée')),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: PracticeColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sort_rounded, color: PracticeColors.textSecondary, size: 17),
                        SizedBox(width: 6),
                        Text('Trier', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
"""
if old_sort in text:
    text = text.replace(old_sort, new_sort, 1)

old_validation = "Ajoutez un motif de consultation et au moins une section clinique : interrogatoire, histoire, examen, bilan ou conduite à tenir."
new_validation = "Ajoutez un motif de consultation et au moins une section clinique : histoire, examen, bilan ou conduite à tenir."
text = text.replace(old_validation, new_validation, 1)

old_clinical_sections = """                  _clinicalSection('1. INTERROGATOIRE', _interrogatoire,
                      'Interrogatoire clinique…'),
                  _doubleClinicalSection(
                      '2. ANTÉCÉDENTS PERSONNELS',
                      'Chirurgicaux',
                      _personalSurgical,
                      'Médicaux',
                      _personalMedical),
                  _doubleClinicalSection(
                      '3. ANTÉCÉDENTS FAMILIAUX',
                      'Chirurgicaux',
                      _familySurgical,
                      'Médicaux',
                      _familyMedical),
                  _clinicalSection('4. MOTIF DE CONSULTATION *',
                      _consultationReason, 'Motif de consultation…'),
                  _clinicalSection('5. HISTOIRE DE LA MALADIE', _illnessHistory,
                      'Chronologie, symptômes, contexte…'),
                  _clinicalSection('6. EXAMEN CLINIQUE', _clinicalExam,
                      'Constantes, examen général et ciblé…'),
                  _clinicalSection('7. EXAMENS COMPLÉMENTAIRES', _complementary,
                      'Biologie, ECG, autres examens…'),
                  _clinicalSection('8. IMAGERIE — CONCLUSION', _imaging,
                      'Radiographie :\\n\\nTDM :\\n\\nÉchographie :\\n\\nIRM :'),
                  _clinicalSection('9. BILAN', _assessment,
                      'Synthèse clinique / diagnostic retenu…'),
                  _clinicalSection('10. CONDUITE À TENIR', _plan,
                      'Traitement, surveillance, orientation…'),
"""
new_clinical_sections = """                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 6, 2, 8),
                    child: Text(
                      'INTERROGATOIRE',
                      style: TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  _doubleClinicalSection(
                      'ANTÉCÉDENTS PERSONNELS',
                      'Chirurgicaux',
                      _personalSurgical,
                      'Médicaux',
                      _personalMedical),
                  _doubleClinicalSection(
                      'ANTÉCÉDENTS FAMILIAUX',
                      'Chirurgicaux',
                      _familySurgical,
                      'Médicaux',
                      _familyMedical),
                  _clinicalSection('MOTIF DE CONSULTATION *',
                      _consultationReason, 'Motif de consultation…'),
                  _clinicalSection('HISTOIRE DE LA MALADIE', _illnessHistory,
                      'Chronologie, symptômes, contexte…'),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 14, 2, 8),
                    child: Text(
                      'EXAMEN ET SYNTHÈSE',
                      style: TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  _clinicalSection('EXAMEN CLINIQUE', _clinicalExam,
                      'Constantes, examen général et ciblé…'),
                  _clinicalSection('EXAMENS COMPLÉMENTAIRES', _complementary,
                      'Biologie, ECG, autres examens…'),
                  _clinicalSection('IMAGERIE — CONCLUSION', _imaging,
                      'Radiographie :\\n\\nTDM :\\n\\nÉchographie :\\n\\nIRM :'),
                  _clinicalSection('BILAN', _assessment,
                      'Synthèse clinique / diagnostic retenu…'),
                  _clinicalSection('CONDUITE À TENIR', _plan,
                      'Traitement, surveillance, orientation…'),
"""
if old_clinical_sections in text:
    text = text.replace(old_clinical_sections, new_clinical_sections, 1)
elif "_clinicalSection('1. INTERROGATOIRE'" in text:
    raise SystemExit('Unexpected clinical sections layout; refusing unsafe patch')

if text == original:
    print('Practice visual patch already applied; no source changes.')
else:
    path.write_text(text, encoding='utf-8')
    print('Practice visual patch applied.')
