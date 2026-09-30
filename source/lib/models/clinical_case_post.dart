class ClinicalCaseQcm {
  final String id;
  final int position;
  final String question;
  final List<String> options;
  final int? correctIndex;
  final String correction;
  final String topic;
  final String generationSource;
  final int? mySelectedIndex;
  final bool? myIsCorrect;
  final DateTime? answeredAt;

  const ClinicalCaseQcm({
    required this.id,
    required this.position,
    required this.question,
    required this.options,
    this.correctIndex,
    this.correction = '',
    this.topic = 'cas_clinique',
    this.generationSource = 'fallback',
    this.mySelectedIndex,
    this.myIsCorrect,
    this.answeredAt,
  });

  bool get answered => mySelectedIndex != null;

  String get topicLabel => ClinicalCasePost.topicLabelFor(topic);

  factory ClinicalCaseQcm.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['options'];
    final options = <String>[];
    if (rawOptions is List) {
      options.addAll(rawOptions.map((value) => '$value'));
    }
    return ClinicalCaseQcm(
      id: '${map['id'] ?? ''}',
      position: int.tryParse('${map['position'] ?? 0}') ?? 0,
      question: '${map['question'] ?? ''}'.trim(),
      options: options,
      correctIndex: map['correct_index'] == null
          ? null
          : int.tryParse('${map['correct_index']}'),
      correction: '${map['correction'] ?? ''}'.trim(),
      topic: '${map['topic'] ?? 'cas_clinique'}'.trim(),
      generationSource: '${map['generation_source'] ?? 'fallback'}'.trim(),
      mySelectedIndex: map['my_selected_index'] == null
          ? null
          : int.tryParse('${map['my_selected_index']}'),
      myIsCorrect:
          map['my_is_correct'] is bool ? map['my_is_correct'] as bool : null,
      answeredAt: DateTime.tryParse('${map['answered_at'] ?? ''}')?.toLocal(),
    );
  }

  ClinicalCaseQcm copyWith({
    int? correctIndex,
    String? correction,
    int? mySelectedIndex,
    bool? myIsCorrect,
    DateTime? answeredAt,
  }) =>
      ClinicalCaseQcm(
        id: id,
        position: position,
        question: question,
        options: options,
        correctIndex: correctIndex ?? this.correctIndex,
        correction: correction ?? this.correction,
        topic: topic,
        generationSource: generationSource,
        mySelectedIndex: mySelectedIndex ?? this.mySelectedIndex,
        myIsCorrect: myIsCorrect ?? this.myIsCorrect,
        answeredAt: answeredAt ?? this.answeredAt,
      );
}

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

  // Champs historiques conservés pour rétrocompatibilité avec les anciens
  // clients. Les nouveaux écrans utilisent [qcms].
  final String question;
  final List<String> options;
  final int correctIndex;
  final String correction;
  final String topic;
  final String generationSource;
  final DateTime? publishedAt;
  final int? mySelectedIndex;
  final bool? myIsCorrect;
  final List<ClinicalCaseQcm> qcms;

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
    this.mySelectedIndex,
    this.myIsCorrect,
    this.qcms = const <ClinicalCaseQcm>[],
  });

  factory ClinicalCasePost.fromMap(Map<String, dynamic> map) {
    final rawOptions = map['qcm_options'];
    final options = <String>[];
    if (rawOptions is List) {
      options.addAll(rawOptions.map((value) => '$value'));
    }

    final parsedQcms = <ClinicalCaseQcm>[];
    final rawQcms = map['qcms'];
    if (rawQcms is List) {
      for (final raw in rawQcms) {
        if (raw is Map) {
          parsedQcms.add(
            ClinicalCaseQcm.fromMap(Map<String, dynamic>.from(raw)),
          );
        }
      }
      parsedQcms.sort((a, b) => a.position.compareTo(b.position));
    }

    final legacyQuestion = '${map['qcm_question'] ?? ''}'.trim();
    final legacyCorrectIndex = int.tryParse('${map['correct_index']}') ?? 0;
    final legacyCorrection = '${map['correction'] ?? ''}'.trim();
    final legacyTopic = '${map['question_topic'] ?? 'cas_clinique'}'.trim();
    final legacySource = '${map['generation_source'] ?? 'fallback'}'.trim();
    final legacySelected = int.tryParse('${map['my_selected_index'] ?? ''}');
    final legacyCorrect =
        map['my_is_correct'] is bool ? map['my_is_correct'] as bool : null;

    // Une ancienne base/ancienne fonction RPC peut ne pas encore renvoyer qcms.
    // Dans ce cas l'application reste utilisable avec le QCM historique.
    if (parsedQcms.isEmpty &&
        legacyQuestion.isNotEmpty &&
        options.length == 4) {
      parsedQcms.add(
        ClinicalCaseQcm(
          id: '${map['id'] ?? ''}',
          position: 1,
          question: legacyQuestion,
          options: options,
          correctIndex: legacySelected == null ? null : legacyCorrectIndex,
          correction: legacySelected == null ? '' : legacyCorrection,
          topic: legacyTopic,
          generationSource: legacySource,
          mySelectedIndex: legacySelected,
          myIsCorrect: legacyCorrect,
        ),
      );
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
      question: legacyQuestion,
      options: options,
      correctIndex: legacyCorrectIndex,
      correction: legacyCorrection,
      topic: legacyTopic,
      generationSource: legacySource,
      publishedAt: DateTime.tryParse('${map['published_at'] ?? ''}')?.toLocal(),
      mySelectedIndex: legacySelected,
      myIsCorrect: legacyCorrect,
      qcms: parsedQcms,
    );
  }

  String get demographicLabel {
    final values = <String>[
      if ((ageBand ?? '').trim().isNotEmpty) ageBand!.trim(),
      if ((sex ?? '').trim().isNotEmpty) sex!.trim(),
    ];
    return values.isEmpty ? 'Patient anonymisé' : values.join(' · ');
  }

  String get topicLabel => topicLabelFor(topic);

  static String topicLabelFor(String topic) {
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
