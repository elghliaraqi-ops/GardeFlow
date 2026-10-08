enum UserRole { medecin, admin }

enum MedicalGrade { junior, senior }

/// Statut affiché à l'inscription. Le grade junior/senior reste le droit métier.
enum MedicalPosition { externe, ffi, interne, resident, professeur }

extension MedicalPositionDetails on MedicalPosition {
  String get label => switch (this) {
        MedicalPosition.externe => 'Médecin Externe',
        MedicalPosition.ffi => 'Médecin FFI',
        MedicalPosition.interne => 'Médecin Interne',
        MedicalPosition.resident => 'Médecin Résident',
        MedicalPosition.professeur => 'Professeur',
      };

  MedicalGrade get grade =>
      this == MedicalPosition.professeur ? MedicalGrade.senior : MedicalGrade.junior;

  bool get requiresPromotion => this == MedicalPosition.interne;

  List<int> get trainingYears => switch (this) {
        MedicalPosition.externe || MedicalPosition.resident => const [1, 2, 3, 4, 5],
        MedicalPosition.ffi => const [6, 7],
        MedicalPosition.interne || MedicalPosition.professeur => const [],
      };

  bool acceptsTrainingYear(int? year) =>
      trainingYears.isEmpty ? year == null : trainingYears.contains(year);
}


enum AccountStatus { pending, active, suspended }

class AppUser {
  final String id;
  final String nom;
  final String prenom;
  final String phone;
  final String passwordHash;
  final String passwordSalt;
  final String service;
  final MedicalGrade grade;
  final MedicalPosition? medicalPosition;
  final int? trainingYear;
  final String hospital;
  final int? promotionNumber;
  final UserRole role;
  final AccountStatus accountStatus;
  final String appearanceTheme;

  AppUser({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.phone,
    required this.passwordHash,
    required this.passwordSalt,
    required this.service,
    required this.grade,
    this.medicalPosition,
    this.trainingYear,
    required this.hospital,
    this.promotionNumber,
    this.role = UserRole.medecin,
    this.accountStatus = AccountStatus.active,
    this.appearanceTheme = 'black',
  });

  AppUser copyWith({
    String? nom,
    String? prenom,
    String? phone,
    String? passwordHash,
    String? passwordSalt,
    String? service,
    MedicalGrade? grade,
    MedicalPosition? medicalPosition,
    bool clearMedicalPosition = false,
    int? trainingYear,
    bool clearTrainingYear = false,
    String? hospital,
    int? promotionNumber,
    bool clearPromotionNumber = false,
    UserRole? role,
    AccountStatus? accountStatus,
    String? appearanceTheme,
  }) {
    return AppUser(
      id: id,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      phone: phone ?? this.phone,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
      service: service ?? this.service,
      grade: grade ?? this.grade,
      medicalPosition: clearMedicalPosition ? null : (medicalPosition ?? this.medicalPosition),
      trainingYear: clearTrainingYear ? null : (trainingYear ?? this.trainingYear),
      hospital: hospital ?? this.hospital,
      promotionNumber: clearPromotionNumber
          ? null
          : (promotionNumber ?? this.promotionNumber),
      role: role ?? this.role,
      accountStatus: accountStatus ?? this.accountStatus,
      appearanceTheme: appearanceTheme ?? this.appearanceTheme,
    );
  }

  String get fullName => '$prenom $nom';
  String get initials {
    final values = <String>[];
    final first = prenom.trim();
    final last = nom.trim();
    if (first.isNotEmpty) values.add(first[0].toUpperCase());
    if (last.isNotEmpty) values.add(last[0].toUpperCase());
    return values.isEmpty ? '?' : values.join();
  }

  String get positionDisplayLabel {
    final base = medicalPosition?.label ?? gradeLabel;
    final year = trainingYear;
    if (year == null) return base;
    return "$"+"base · $"+"{year == 1 ? '1re' : '${year}e'} année";
  }

  String get gradeLabel => grade == MedicalGrade.senior ? 'Senior' : 'Junior';
  String get roleLabel => role == UserRole.admin ? 'Administrateur' : 'Médecin';

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'prenom': prenom,
    'phone': phone,
    'passwordHash': passwordHash,
    'passwordSalt': passwordSalt,
    'service': service,
    'grade': grade.name,
    'medicalPosition': medicalPosition?.name,
    'trainingYear': trainingYear,
    'hospital': hospital,
    'promotionNumber': promotionNumber,
    'role': role.name,
    'accountStatus': accountStatus.name,
    'appearanceTheme': appearanceTheme,
  };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final legacyFonction = (json['fonction'] as String?)?.toLowerCase();
    final rawGrade = (json['grade'] as String?)?.toLowerCase();
    final grade = rawGrade == 'senior' || legacyFonction == 'senior'
        ? MedicalGrade.senior
        : MedicalGrade.junior;
    final rawMedicalPosition =
        (json['medicalPosition'] ?? json['medical_position'])?.toString();
    MedicalPosition? medicalPosition;
    for (final value in MedicalPosition.values) {
      if (value.name == rawMedicalPosition) {
        medicalPosition = value;
        break;
      }
    }
    final rawAppearance =
        (json['appearanceTheme'] as String?) ??
        (json['appearance_theme'] as String?);
    const allowedAppearance = <String>{'green', 'red', 'white', 'black'};
    final appearanceTheme = allowedAppearance.contains(rawAppearance)
        ? rawAppearance!
        : 'black';
    return AppUser(
      id: (json['id'] as String?) ?? (json['phone'] as String? ?? ''),
      nom: json['nom'] as String,
      prenom: json['prenom'] as String,
      phone: json['phone'] as String,
      passwordHash: (json['passwordHash'] as String?) ?? '',
      passwordSalt: (json['passwordSalt'] as String?) ?? '',
      service: json['service'] as String,
      grade: grade,
      medicalPosition: medicalPosition,
      trainingYear: ((json['trainingYear'] ?? json['training_year']) as num?)?.toInt(),
      hospital: json['hospital'] as String,
      promotionNumber:
          (json['promotionNumber'] as num?)?.toInt() ??
          (json['promotion_number'] as num?)?.toInt(),
      role: UserRole.values.byName((json['role'] as String?) ?? 'medecin'),
      accountStatus: AccountStatus.values.byName(
        (json['accountStatus'] as String?) ?? 'active',
      ),
      appearanceTheme: appearanceTheme,
    );
  }
}
