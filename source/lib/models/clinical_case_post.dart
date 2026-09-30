class ClinicalCasePost {
  final String id;
  final String? ageBand;
  final String? sex;
  final String presentation;
  final String history;
  final String clinicalExam;
  final String complementaryExams;
  final String imagingConclusion;
  final String assessment;
  final String plan;
  final String disposition;
  final String? specialistService;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String correction;
  final String topic;
  final String generationSource;
  final DateTime? publishedAt;

  const ClinicalCasePost({
    required this.id,
    this.ageBand,
    this.sex,
    this.presentation = '',
    this.history = '',
    this.clinicalExam = '',
    this.complementaryExams = '',
    this.imagingConclusion = '',
    this.assessment = '',
    this.plan = '',
    this.disposition = '',
    this.specialistService,
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.correction,
    required this.topic,
    required this.generationSource,
    this.publishedAt,
  });

  factory ClinicalCasePost.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['qcm_options'];
    final options = <String>[];
    if (rawOptions is List) {
      options.addAll(rawOptions.map((value) => '$value'));
    }
    return ClinicalCasePost(
      id: '${map['id'] ?? ''}',
      ageBand: _nullable(map['age_band']),
      sex: _nullable(map['sex']),
      presentation: '${map['presentation'] ?? ''}'.trim(),
      history: '${map['history'] ?? ''}'.trim(),
      clinicalExam: '${map['clinical_exam'] ?? ''}'.trim(),
      complementaryExams: '${map['complementary_exams'] ?? ''}'.trim(),
      imagingConclusion: '${map['imaging_conclusion'] ?? ''}'.trim(),
      assessment: '${map['assessment'] ?? ''}'.trim(),
      plan: '${map['plan'] ?? ''}'.trim(),
      disposition: '${map['disposition'] ?? ''}'.trim(),
      specialistService: _nullable(map['specialist_service']),
      question: '${map['qcm_question'] ?? ''}'.trim(),
      options: options,
      correctIndex: int.tryParse('${map['correct_index']}') ?? 0,
      correction: '${map['correction'] ?? ''}'.trim(),
      topic: '${map['question_topic'] ?? 'cas_clinique'}'.trim(),
      generationSource: '${map['generation_source'] ?? 'fallback'}'.trim(),
      publishedAt: DateTime.tryParse('${map['published_at'] ?? ''}')?.toLocal(),
    );
  }

  String get demographicLabel {
    final values = <String>[
      if ((ageBand ?? '').trim().isNotEmpty) ageBand!.trim(),
      if ((sex ?? '').trim().isNotEmpty) sex!.trim(),
    ];
    return values.isEmpty ? 'Patient anonymisé' : values.join(' · ');
  }

  String get topicLabel {
    switch (topic) {
      case 'motif':
        return 'Motif';
      case 'symptome':
        return 'Symptôme';
      case 'examen':
        return 'Examen clinique';
      case 'imagerie':
        return 'Imagerie';
      case 'synthese':
        return 'Synthèse';
      case 'prise_en_charge':
        return 'Prise en charge';
      case 'orientation':
        return 'Orientation';
      case 'avis_specialise':
        return 'Avis spécialisé';
      default:
        return 'Cas clinique';
    }
  }

  static String? _nullable(dynamic value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}
