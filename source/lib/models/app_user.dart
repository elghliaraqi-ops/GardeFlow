enum UserRole { medecin, admin }
enum MedicalGrade { junior, senior }
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
  final String hospital;
  final int? promotionNumber;
  final UserRole role;
  final AccountStatus accountStatus;

  AppUser({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.phone,
    required this.passwordHash,
    required this.passwordSalt,
    required this.service,
    required this.grade,
    required this.hospital,
    this.promotionNumber,
    this.role = UserRole.medecin,
    this.accountStatus = AccountStatus.active,
  });

  String get fullName => '$prenom $nom';
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
        'hospital': hospital,
        'promotionNumber': promotionNumber,
        'role': role.name,
        'accountStatus': accountStatus.name,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final legacyFonction = (json['fonction'] as String?)?.toLowerCase();
    final rawGrade = (json['grade'] as String?)?.toLowerCase();
    final grade = rawGrade == 'senior' || legacyFonction == 'senior'
        ? MedicalGrade.senior
        : MedicalGrade.junior;
    return AppUser(
      id: (json['id'] as String?) ?? (json['phone'] as String? ?? ''),
      nom: json['nom'] as String,
      prenom: json['prenom'] as String,
      phone: json['phone'] as String,
      passwordHash: (json['passwordHash'] as String?) ?? '',
      passwordSalt: (json['passwordSalt'] as String?) ?? '',
      service: json['service'] as String,
      grade: grade,
      hospital: json['hospital'] as String,
      promotionNumber: (json['promotionNumber'] as num?)?.toInt() ??
          (json['promotion_number'] as num?)?.toInt(),
      role: UserRole.values.byName((json['role'] as String?) ?? 'medecin'),
      accountStatus: AccountStatus.values.byName((json['accountStatus'] as String?) ?? 'active'),
    );
  }
}
