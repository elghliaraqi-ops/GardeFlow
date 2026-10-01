import '../models/clinical_case_post.dart';

extension ClinicalCaseSpecialty on ClinicalCasePost {
  String get specialtyLabel {
    final direct = (specialistService ?? '').trim();
    final directMatch = _matchSpecialty(_normalize(direct));
    if (directMatch != null) return directMatch;

    final corpus = _normalize(<String>[
      ageBand ?? '',
      presentation,
      history,
      clinicalExam,
      complementaryExams,
      imagingConclusion,
      assessment,
      plan,
      disposition,
      topic,
    ].join(' '));

    return _matchSpecialty(corpus) ?? 'Médecine générale';
  }

  static String? _matchSpecialty(String text) {
    if (text.trim().isEmpty) return null;

    bool has(List<String> terms) => terms.any(text.contains);

    if (has(<String>[
      'gynec',
      'obstet',
      'grossess',
      'enceinte',
      'partum',
      'uter',
      'ovar',
      'metrorrag',
    ])) {
      return 'Gynécologie-Obstétrique';
    }
    if (has(<String>[
      'pediatr',
      'nourrisson',
      'nouveau-ne',
      'enfant',
      'bronchiolite',
    ])) {
      return 'Pédiatrie';
    }
    if (has(<String>[
      'cardio',
      'coronar',
      'infarct',
      'troponin',
      'angor',
      'arythm',
      'fibrillation atriale',
      'insuffisance cardiaque',
      'oedeme aigu pulmonaire',
      'pericard',
    ])) {
      return 'Cardiologie';
    }
    if (has(<String>[
      'pneumo',
      'asthm',
      'bpco',
      'pneumopath',
      'pleur',
      'hemopty',
      'embolie pulmonaire',
      'detresse respiratoire',
    ])) {
      return 'Pneumologie';
    }
    if (has(<String>[
      'neuro',
      'avc',
      'accident vasculaire cerebral',
      'epilep',
      'convuls',
      'mening',
      'cephalee',
      'deficit neurologique',
    ])) {
      return 'Neurologie';
    }
    if (has(<String>[
      'urolog',
      'nephro',
      'renal',
      'rein',
      'colique nephretique',
      'hematur',
      'pyeloneph',
      'retention urinaire',
    ])) {
      return 'Urologie-Néphrologie';
    }
    if (has(<String>[
      'chirurgie viscerale',
      'visceral',
      'appendic',
      'occlusion',
      'periton',
      'hernie',
      'cholecyst',
      'perforation digestive',
      'abdomen aigu',
      'laparotom',
    ])) {
      return 'Chirurgie viscérale';
    }
    if (has(<String>[
      'gastro',
      'digestif',
      'pancreat',
      'cirrho',
      'hepatit',
      'hematemes',
      'melena',
      'diarrh',
      'colit',
    ])) {
      return 'Gastro-entérologie';
    }
    if (has(<String>[
      'traumato',
      'orthoped',
      'fractur',
      'luxation',
      'entorse',
      'polytrauma',
      'traumatisme osseux',
    ])) {
      return 'Traumatologie-Orthopédie';
    }
    if (has(<String>[
      'endocrino',
      'diabet',
      'thyroid',
      'hypoglycem',
      'hyperglycem',
      'acidocetose',
    ])) {
      return 'Endocrinologie';
    }
    if (has(<String>[
      'infectio',
      'sepsis',
      'septique',
      'infection',
      'fievre',
      'palud',
      'tubercul',
    ])) {
      return 'Infectiologie';
    }
    if (has(<String>[
      'hemato',
      'oncolog',
      'cancer',
      'leucem',
      'lymphom',
      'anemie severe',
      'neoplas',
    ])) {
      return 'Hématologie-Oncologie';
    }
    if (has(<String>[
      'orl',
      'otorhino',
      'angine',
      'otite',
      'epistaxis',
      'laryng',
    ])) {
      return 'ORL';
    }
    if (has(<String>[
      'ophtal',
      'oculaire',
      'oeil',
      'glaucome',
      'retin',
    ])) {
      return 'Ophtalmologie';
    }
    if (has(<String>[
      'dermato',
      'cutane',
      'eruption',
      'urticaire',
      'eczema',
    ])) {
      return 'Dermatologie';
    }
    if (has(<String>[
      'psychi',
      'suicid',
      'psychose',
      'depress',
      'agitation psychiatrique',
    ])) {
      return 'Psychiatrie';
    }
    if (has(<String>[
      'reanimation',
      'anesthes',
      'choc',
      'ventilation mecanique',
      'intub',
      'vasopress',
    ])) {
      return 'Anesthésie-Réanimation';
    }
    if (has(<String>[
      'medecine interne',
      'systemique',
      'lupus',
      'vascularite',
      'auto-immune',
    ])) {
      return 'Médecine interne';
    }

    return null;
  }

  static String _normalize(String value) {
    var text = value.toLowerCase().trim();
    const replacements = <String, String>{
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'á': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'œ': 'oe',
      '’': "'",
    };
    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }
}
