import '../models/app_user.dart';
import '../models/planning_entry.dart';

const practiceEmergencyShiftIds = <String>{
  'urg-jour',
  'urg-nuit',
  'urg-24h',
};

class PracticeGuard {
  final PlanningEntry entry;
  final DateTime start;
  final DateTime end;

  const PracticeGuard({
    required this.entry,
    required this.start,
    required this.end,
  });

  String get id => entry.id;
  String get shiftId => entry.shiftId;
  String get dateStr => entry.dateStr;
  bool get isDisciplinary => entry.isDisciplinary;

  String get periodLabel {
    switch (shiftId) {
      case 'urg-nuit':
        return 'Nuit';
      case 'urg-24h':
        return '24H';
      default:
        return 'Jour';
    }
  }

  String get timeLabel {
    switch (shiftId) {
      case 'urg-nuit':
        return '20:00 → 08:00';
      case 'urg-24h':
        return '08:00 → 08:00';
      default:
        return '08:00 → 20:00';
    }
  }

  String get title => 'Garde Urgences · $periodLabel';

  bool isActiveAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);

  static PracticeGuard? fromEntry(PlanningEntry entry) {
    if (!practiceEmergencyShiftIds.contains(entry.shiftId)) return null;
    final day = DateTime.tryParse(entry.dateStr);
    if (day == null) return null;
    late DateTime start;
    late DateTime end;
    switch (entry.shiftId) {
      case 'urg-nuit':
        // La date du planning est toujours la date de début de garde.
        // Ex. tuile 29/09 = 29/09 20h -> 30/09 08h.
        start = DateTime(day.year, day.month, day.day, 20);
        end = DateTime(day.year, day.month, day.day + 1, 8);
        break;
      case 'urg-24h':
        start = DateTime(day.year, day.month, day.day, 8);
        end = DateTime(day.year, day.month, day.day + 1, 8);
        break;
      default:
        start = DateTime(day.year, day.month, day.day, 8);
        end = DateTime(day.year, day.month, day.day, 20);
    }
    return PracticeGuard(entry: entry, start: start, end: end);
  }

  static PracticeGuard? current({
    required Iterable<PlanningEntry> entries,
    required AppUser user,
    DateTime? now,
  }) {
    final instant = now ?? DateTime.now();
    final matches = <PracticeGuard>[];
    for (final entry in entries) {
      final belongsToUser = entry.ownerId == user.id ||
          (entry.ownerPhone.isNotEmpty && entry.ownerPhone == user.phone);
      if (!belongsToUser) continue;
      final guard = PracticeGuard.fromEntry(entry);
      if (guard != null && guard.isActiveAt(instant)) matches.add(guard);
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => b.start.compareTo(a.start));
    return matches.first;
  }
}

class PracticeCase {
  final String? id;
  final String userId;
  final String guardId;
  final String guardDate;
  final String guardShiftId;
  final String clientId;
  final int patientNumber;
  final int? age;
  final String? sex;
  final DateTime? arrivalTime;
  final String? location;
  final String? chiefComplaint;
  final String interrogatoire;
  final String personalSurgicalHistory;
  final String personalMedicalHistory;
  final String familySurgicalHistory;
  final String familyMedicalHistory;
  final String consultationReason;
  final String illnessHistory;
  final String clinicalExam;
  final String complementaryExams;
  final String imagingConclusion;
  final String assessment;
  final String plan;
  final bool specialistOpinionRequested;
  final String? specialistService;
  final bool specialistOpinionDone;
  final bool waiting;
  final bool prescriptionDone;
  final bool discharged;
  final bool hospitalized;
  final String? hospitalizationService;
  final bool isDraft;
  final DateTime? syncedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool pendingSync;

  const PracticeCase({
    this.id,
    required this.userId,
    required this.guardId,
    required this.guardDate,
    required this.guardShiftId,
    required this.clientId,
    required this.patientNumber,
    this.age,
    this.sex,
    this.arrivalTime,
    this.location,
    this.chiefComplaint,
    this.interrogatoire = '',
    this.personalSurgicalHistory = '',
    this.personalMedicalHistory = '',
    this.familySurgicalHistory = '',
    this.familyMedicalHistory = '',
    this.consultationReason = '',
    this.illnessHistory = '',
    this.clinicalExam = '',
    this.complementaryExams = '',
    this.imagingConclusion = '',
    this.assessment = '',
    this.plan = '',
    this.specialistOpinionRequested = false,
    this.specialistService,
    this.specialistOpinionDone = false,
    this.waiting = false,
    this.prescriptionDone = false,
    this.discharged = false,
    this.hospitalized = false,
    this.hospitalizationService,
    this.isDraft = true,
    this.syncedAt,
    this.createdAt,
    this.updatedAt,
    this.pendingSync = false,
  });

  String get patientLabel => 'Patient #${patientNumber.toString().padLeft(3, '0')}';

  bool get isValid {
    if (consultationReason.trim().isEmpty) return false;
    return <String>[
      interrogatoire,
      illnessHistory,
      clinicalExam,
      assessment,
      plan,
    ].any((value) => value.trim().isNotEmpty);
  }

  bool get isComplete => isValid &&
      (interrogatoire.trim().isNotEmpty || illnessHistory.trim().isNotEmpty) &&
      clinicalExam.trim().isNotEmpty &&
      assessment.trim().isNotEmpty &&
      plan.trim().isNotEmpty;

  int get xp => isDraft || !isValid ? 0 : 10 + (isComplete ? 2 : 0);

  String get displayReason {
    final reason = consultationReason.trim();
    if (reason.isNotEmpty) return reason;
    final chief = chiefComplaint?.trim() ?? '';
    return chief.isEmpty ? 'Observation en cours' : chief;
  }

  Map<String, dynamic> toMap({bool includeId = true}) => <String, dynamic>{
        if (includeId && id != null) 'id': id,
        'user_id': userId,
        'guard_id': guardId,
        'guard_date': guardDate,
        'guard_shift_id': guardShiftId,
        'client_id': clientId,
        'patient_number': patientNumber,
        'age': age,
        'sex': sex,
        'arrival_time': arrivalTime?.toUtc().toIso8601String(),
        'location': _nullIfBlank(location),
        'chief_complaint': _nullIfBlank(chiefComplaint),
        'interrogatoire': interrogatoire,
        'personal_surgical_history': personalSurgicalHistory,
        'personal_medical_history': personalMedicalHistory,
        'family_surgical_history': familySurgicalHistory,
        'family_medical_history': familyMedicalHistory,
        'consultation_reason': consultationReason,
        'illness_history': illnessHistory,
        'clinical_exam': clinicalExam,
        'complementary_exams': complementaryExams,
        'imaging_conclusion': imagingConclusion,
        'assessment': assessment,
        'plan': plan,
        'specialist_opinion_requested': specialistOpinionRequested,
        'specialist_service': specialistOpinionRequested ? _nullIfBlank(specialistService) : null,
        'specialist_opinion_done': specialistOpinionRequested && specialistOpinionDone,
        'waiting': waiting,
        'prescription_done': prescriptionDone,
        'discharged': discharged,
        'hospitalized': hospitalized,
        'hospitalization_service': hospitalized ? _nullIfBlank(hospitalizationService) : null,
        'is_draft': isDraft,
        'synced_at': syncedAt?.toUtc().toIso8601String(),
      };

  factory PracticeCase.fromMap(Map<String, dynamic> map, {bool pendingSync = false}) {
    return PracticeCase(
      id: map['id']?.toString(),
      userId: map['user_id']?.toString() ?? '',
      guardId: map['guard_id']?.toString() ?? '',
      guardDate: map['guard_date']?.toString() ?? '',
      guardShiftId: map['guard_shift_id']?.toString() ?? '',
      clientId: map['client_id']?.toString() ?? '',
      patientNumber: _asInt(map['patient_number']),
      age: map['age'] == null ? null : _asInt(map['age']),
      sex: map['sex']?.toString(),
      arrivalTime: _asDate(map['arrival_time']),
      location: map['location']?.toString(),
      chiefComplaint: map['chief_complaint']?.toString(),
      interrogatoire: map['interrogatoire']?.toString() ?? '',
      personalSurgicalHistory: map['personal_surgical_history']?.toString() ?? '',
      personalMedicalHistory: map['personal_medical_history']?.toString() ?? '',
      familySurgicalHistory: map['family_surgical_history']?.toString() ?? '',
      familyMedicalHistory: map['family_medical_history']?.toString() ?? '',
      consultationReason: map['consultation_reason']?.toString() ?? '',
      illnessHistory: map['illness_history']?.toString() ?? '',
      clinicalExam: map['clinical_exam']?.toString() ?? '',
      complementaryExams: map['complementary_exams']?.toString() ?? '',
      imagingConclusion: map['imaging_conclusion']?.toString() ?? '',
      assessment: map['assessment']?.toString() ?? '',
      plan: map['plan']?.toString() ?? '',
      specialistOpinionRequested: map['specialist_opinion_requested'] == true,
      specialistService: map['specialist_service']?.toString(),
      specialistOpinionDone: map['specialist_opinion_done'] == true,
      waiting: map['waiting'] == true,
      prescriptionDone: map['prescription_done'] == true,
      discharged: map['discharged'] == true,
      hospitalized: map['hospitalized'] == true,
      hospitalizationService: map['hospitalization_service']?.toString(),
      isDraft: map['is_draft'] != false,
      syncedAt: _asDate(map['synced_at']),
      createdAt: _asDate(map['created_at']),
      updatedAt: _asDate(map['updated_at']),
      pendingSync: pendingSync,
    );
  }

  PracticeCase copyWith({
    String? id,
    int? patientNumber,
    bool? isDraft,
    DateTime? syncedAt,
    bool? pendingSync,
  }) => PracticeCase(
        id: id ?? this.id,
        userId: userId,
        guardId: guardId,
        guardDate: guardDate,
        guardShiftId: guardShiftId,
        clientId: clientId,
        patientNumber: patientNumber ?? this.patientNumber,
        age: age,
        sex: sex,
        arrivalTime: arrivalTime,
        location: location,
        chiefComplaint: chiefComplaint,
        interrogatoire: interrogatoire,
        personalSurgicalHistory: personalSurgicalHistory,
        personalMedicalHistory: personalMedicalHistory,
        familySurgicalHistory: familySurgicalHistory,
        familyMedicalHistory: familyMedicalHistory,
        consultationReason: consultationReason,
        illnessHistory: illnessHistory,
        clinicalExam: clinicalExam,
        complementaryExams: complementaryExams,
        imagingConclusion: imagingConclusion,
        assessment: assessment,
        plan: plan,
        specialistOpinionRequested: specialistOpinionRequested,
        specialistService: specialistService,
        specialistOpinionDone: specialistOpinionDone,
        waiting: waiting,
        prescriptionDone: prescriptionDone,
        discharged: discharged,
        hospitalized: hospitalized,
        hospitalizationService: hospitalizationService,
        isDraft: isDraft ?? this.isDraft,
        syncedAt: syncedAt ?? this.syncedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        pendingSync: pendingSync ?? this.pendingSync,
      );

  static String? _nullIfBlank(String? value) {
    final cleaned = value?.trim() ?? '';
    return cleaned.isEmpty ? null : cleaned;
  }

  static int _asInt(dynamic value) => value is int ? value : int.tryParse('$value') ?? 0;
  static DateTime? _asDate(dynamic value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();
}

class PracticeStats {
  final int patients;
  final int waiting;
  final int discharged;
  final int hospitalized;
  final int specialistOpinions;
  final int prescriptions;
  final int completeObservations;
  final int guardsCount;
  final double averagePerGuard;
  final int bestGuard;
  final int xp;
  final int streak;

  const PracticeStats({
    this.patients = 0,
    this.waiting = 0,
    this.discharged = 0,
    this.hospitalized = 0,
    this.specialistOpinions = 0,
    this.prescriptions = 0,
    this.completeObservations = 0,
    this.guardsCount = 0,
    this.averagePerGuard = 0,
    this.bestGuard = 0,
    this.xp = 0,
    this.streak = 0,
  });

  factory PracticeStats.fromMap(Map<String, dynamic>? map) => PracticeStats(
        patients: _int(map?['patients']),
        waiting: _int(map?['waiting']),
        discharged: _int(map?['discharged']),
        hospitalized: _int(map?['hospitalized']),
        specialistOpinions: _int(map?['specialist_opinions']),
        prescriptions: _int(map?['prescriptions']),
        completeObservations: _int(map?['complete_observations']),
        guardsCount: _int(map?['guards_count']),
        averagePerGuard: _double(map?['average_per_guard']),
        bestGuard: _int(map?['best_guard']),
        xp: _int(map?['xp']),
        streak: _int(map?['streak']),
      );

  static int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
  static double _double(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
}

class PracticePreferences {
  final bool leaderboardOptIn;
  final int? guardGoal;
  const PracticePreferences({this.leaderboardOptIn = true, this.guardGoal});

  factory PracticePreferences.fromMap(Map<String, dynamic>? map) => PracticePreferences(
        leaderboardOptIn: map?['leaderboard_opt_in'] != false,
        guardGoal: map?['guard_goal'] == null ? null : int.tryParse('${map?['guard_goal']}'),
      );
}

class PracticeRanks {
  final int? globalRank;
  final int? promotionRank;
  final bool hasActivity;
  final bool leaderboardOptIn;
  const PracticeRanks({this.globalRank, this.promotionRank, this.hasActivity = false, this.leaderboardOptIn = true});

  factory PracticeRanks.fromMap(Map<String, dynamic>? map) => PracticeRanks(
        globalRank: _nullableInt(map?['global_rank']),
        promotionRank: _nullableInt(map?['promotion_rank']),
        hasActivity: map?['has_activity'] == true,
        leaderboardOptIn: map?['leaderboard_opt_in'] != false,
      );

  static int? _nullableInt(dynamic value) => value == null ? null : int.tryParse('$value');
}

class PracticeRankEntry {
  final int rank;
  final String userId;
  final String displayName;
  final int? promotionNumber;
  final String hospital;
  final int xp;
  final int caseCount;
  const PracticeRankEntry({required this.rank, required this.userId, required this.displayName, this.promotionNumber, required this.hospital, required this.xp, required this.caseCount});

  factory PracticeRankEntry.fromMap(Map<String, dynamic> map) => PracticeRankEntry(
        rank: int.tryParse('${map['rank']}') ?? 0,
        userId: '${map['user_id'] ?? ''}',
        displayName: '${map['display_name'] ?? 'Médecin'}',
        promotionNumber: map['promotion_number'] == null ? null : int.tryParse('${map['promotion_number']}'),
        hospital: '${map['hospital'] ?? ''}',
        xp: int.tryParse('${map['xp']}') ?? 0,
        caseCount: int.tryParse('${map['case_count']}') ?? 0,
      );
}

class PracticeAchievement {
  final String key;
  final String name;
  final String description;
  final int threshold;
  final String icon;
  final int progress;
  final DateTime? unlockedAt;
  const PracticeAchievement({required this.key, required this.name, required this.description, required this.threshold, required this.icon, required this.progress, this.unlockedAt});

  bool get unlocked => unlockedAt != null || progress >= threshold;
  double get ratio => threshold <= 0 ? 0 : (progress / threshold).clamp(0.0, 1.0);

  factory PracticeAchievement.fromMap(Map<String, dynamic> map) => PracticeAchievement(
        key: '${map['key'] ?? ''}',
        name: '${map['name'] ?? ''}',
        description: '${map['description'] ?? ''}',
        threshold: int.tryParse('${map['threshold']}') ?? 1,
        icon: '${map['icon'] ?? 'military_tech'}',
        progress: int.tryParse('${map['progress']}') ?? 0,
        unlockedAt: map['unlocked_at'] == null ? null : DateTime.tryParse('${map['unlocked_at']}')?.toLocal(),
      );
}

class PracticeLevel {
  final int number;
  final String name;
  final int floorXp;
  final int ceilingXp;
  const PracticeLevel(this.number, this.name, this.floorXp, this.ceilingXp);

  double progressFor(int xp) {
    if (ceilingXp <= floorXp) return 1;
    return ((xp - floorXp) / (ceilingXp - floorXp)).clamp(0.0, 1.0);
  }

  int xpIntoLevel(int xp) => (xp - floorXp).clamp(0, ceilingXp - floorXp);
  int get xpForLevel => ceilingXp - floorXp;
}

const practiceLevels = <PracticeLevel>[
  PracticeLevel(1, 'Débutant', 0, 100),
  PracticeLevel(2, 'Interne actif', 100, 250),
  PracticeLevel(3, 'Interne régulier', 250, 500),
  PracticeLevel(4, 'Interne engagé', 500, 900),
  PracticeLevel(5, 'Interne confirmé', 900, 1500),
  PracticeLevel(6, 'Documentation avancée', 1500, 2300),
  PracticeLevel(7, 'Progression structurée', 2300, 3300),
  PracticeLevel(8, 'Pratique assidue', 3300, 5000),
  PracticeLevel(9, 'Pratique expérimentée', 5000, 7500),
  PracticeLevel(10, 'Référent Practice', 7500, 1000000),
];

PracticeLevel practiceLevelForXp(int xp) {
  for (final level in practiceLevels) {
    if (xp < level.ceilingXp) return level;
  }
  return practiceLevels.last;
}
