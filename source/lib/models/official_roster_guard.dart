enum OfficialRosterReviewStatus { green, orange, red }

enum OfficialDoctorMatchStatus {
  matched,
  unregistered,
  ambiguous,
  manualReview,
}

class OfficialRosterDoctorIdentity {
  final String firstName;
  final String lastName;
  final String fullName;

  const OfficialRosterDoctorIdentity({
    required this.firstName,
    required this.lastName,
    required this.fullName,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'full_name': fullName,
      };

  factory OfficialRosterDoctorIdentity.fromJson(Map<String, dynamic> json) {
    return OfficialRosterDoctorIdentity(
      firstName: (json['first_name'] ?? '').toString().trim(),
      lastName: (json['last_name'] ?? '').toString().trim(),
      fullName: (json['full_name'] ?? '').toString().trim(),
    );
  }
}

class OfficialRosterGuard {
  final String dateStr;
  final String shiftId;
  final String dutyArea = 'urgences';
  final String hospital;
  final OfficialRosterDoctorIdentity identity;
  final double confidence;
  final OfficialRosterReviewStatus reviewStatus;
  final int? pageNumber;
  final String? zone;
  final bool isDisciplinary;
  final String? matchedProfileId;
  final OfficialDoctorMatchStatus matchStatus;

  const OfficialRosterGuard({
    required this.dateStr,
    required this.shiftId,
    required this.hospital,
    required this.identity,
    required this.confidence,
    required this.reviewStatus,
    required this.matchStatus,
    this.pageNumber,
    this.zone,
    this.isDisciplinary = false,
    this.matchedProfileId,
  });

  String get displayName => identity.fullName.isNotEmpty
      ? identity.fullName
      : '${identity.firstName} ${identity.lastName}'.trim();

  bool get mayCreatePersonalAssignment =>
      reviewStatus != OfficialRosterReviewStatus.red &&
      confidence >= 0.90 &&
      matchStatus == OfficialDoctorMatchStatus.matched &&
      matchedProfileId != null &&
      matchedProfileId!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'date': dateStr,
        'shift_id': shiftId,
        'duty_area': dutyArea,
        'hospital': hospital,
        ...identity.toJson(),
        'confidence': confidence,
        'review_status': reviewStatus.name,
        'page_number': pageNumber,
        'zone': zone,
        'is_disciplinary': isDisciplinary,
        'matched_profile_id': matchedProfileId,
        'match_status': matchStatus.name,
      };
}
