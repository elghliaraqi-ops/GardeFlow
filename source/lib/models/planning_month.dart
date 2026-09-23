enum PlanningMonthStatus { draft, submitted, approved, rejected }

class PlanningMonth {
  final String ownerId;
  final int year;
  final int month;
  PlanningMonthStatus status;
  DateTime? submittedAt;
  DateTime? reviewedAt;
  String? reviewedBy;
  String? rejectionReason;

  PlanningMonth({
    required this.ownerId,
    required this.year,
    required this.month,
    this.status = PlanningMonthStatus.draft,
    this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  String get key => '$ownerId-$year-${month.toString().padLeft(2, '0')}';
  DateTime get monthDate => DateTime(year, month, 1);
  bool get isEditable => status != PlanningMonthStatus.approved;
  bool get isSubmitted => status == PlanningMonthStatus.submitted; // état historique V10.1
  bool get isApproved => status == PlanningMonthStatus.approved;

  Map<String, dynamic> toJson() => {
        'ownerId': ownerId,
        'year': year,
        'month': month,
        'status': status.name,
        'submittedAt': submittedAt?.toIso8601String(),
        'reviewedAt': reviewedAt?.toIso8601String(),
        'reviewedBy': reviewedBy,
        'rejectionReason': rejectionReason,
      };

  factory PlanningMonth.fromJson(Map<String, dynamic> json) => PlanningMonth(
        ownerId: json['ownerId'] as String,
        year: (json['year'] as num).toInt(),
        month: (json['month'] as num).toInt(),
        status: PlanningMonthStatus.values.byName((json['status'] as String?) ?? 'draft'),
        submittedAt: json['submittedAt'] == null ? null : DateTime.parse(json['submittedAt'] as String),
        reviewedAt: json['reviewedAt'] == null ? null : DateTime.parse(json['reviewedAt'] as String),
        reviewedBy: json['reviewedBy'] as String?,
        rejectionReason: json['rejectionReason'] as String?,
      );
}
