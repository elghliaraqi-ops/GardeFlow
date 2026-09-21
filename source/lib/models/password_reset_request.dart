class PasswordResetRequest {
  final String id;
  final String profileId;
  final DateTime requestedAt;
  final String fullName;
  final String phone;
  final String hospital;
  final String service;
  final String gradeLabel;

  const PasswordResetRequest({
    required this.id,
    required this.profileId,
    required this.requestedAt,
    required this.fullName,
    required this.phone,
    required this.hospital,
    required this.service,
    required this.gradeLabel,
  });

  factory PasswordResetRequest.fromJson(Map<String, dynamic> json) {
    return PasswordResetRequest(
      id: json['request_id'].toString(),
      profileId: json['profile_id'].toString(),
      requestedAt: DateTime.parse(json['requested_at'].toString()),
      fullName: (json['full_name'] as String?)?.trim() ?? '',
      phone: (json['phone'] as String?) ?? '',
      hospital: (json['hospital'] as String?) ?? '',
      service: (json['service'] as String?) ?? '',
      gradeLabel: (json['grade_label'] as String?) ?? 'Médecin',
    );
  }
}
