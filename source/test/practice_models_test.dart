import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/app_user.dart';
import 'package:huim6_planning/models/planning_entry.dart';
import 'package:huim6_planning/models/practice_models.dart';

void main() {
  group('PracticeGuard', () {
    final user = AppUser(
      id: 'user-1',
      nom: 'TEST',
      prenom: 'Dr',
      phone: '+212600000000',
      passwordHash: '',
      passwordSalt: '',
      service: 'Imagerie Médicale',
      grade: MedicalGrade.junior,
      hospital: 'HUIM6 Bouskoura',
      promotionNumber: 6,
    );

    PlanningEntry entry(
      String shift,
      String date, {
      bool isDisciplinary = false,
    }) => PlanningEntry(
          id: '$shift-$date${isDisciplinary ? '-disciplinary' : ''}',
          dateStr: date,
          shiftId: shift,
          ownerId: user.id,
          ownerPhone: user.phone,
          ownerName: user.fullName,
          isDisciplinary: isDisciplinary,
        );

    test('night tile date is the start date', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-nuit', '2026-10-01')],
        user: user,
        now: DateTime(2026, 10, 1, 20, 3),
      );
      expect(guard, isNotNull);
      expect(guard!.periodLabel, 'Nuit');
      expect(guard.start, DateTime(2026, 10, 1, 20));
      expect(guard.end, DateTime(2026, 10, 2, 8));
    });

    test('same night guard stays active after midnight until 08:00', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-nuit', '2026-10-01')],
        user: user,
        now: DateTime(2026, 10, 2, 2, 30),
      );
      expect(guard, isNotNull);
      expect(guard!.start, DateTime(2026, 10, 1, 20));
      expect(guard.end, DateTime(2026, 10, 2, 8));
    });

    test('planning date is the start date for any day guard', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-jour', '2026-11-07')],
        user: user,
        now: DateTime(2026, 11, 7, 12),
      );
      expect(guard, isNotNull);
      expect(guard!.start, DateTime(2026, 11, 7, 8));
      expect(guard.end, DateTime(2026, 11, 7, 20));
    });

    test('planning date is the start date for any 24H guard', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-24h', '2026-06-03')],
        user: user,
        now: DateTime(2026, 6, 3, 23),
      );
      expect(guard, isNotNull);
      expect(guard!.start, DateTime(2026, 6, 3, 8));
      expect(guard.end, DateTime(2026, 6, 4, 8));
    });

    test('night guard rolls correctly across month boundaries', () {
      final guard = PracticeGuard.fromEntry(entry('urg-nuit', '2026-09-30'));
      expect(guard, isNotNull);
      expect(guard!.start, DateTime(2026, 9, 30, 20));
      expect(guard.end, DateTime(2026, 10, 1, 8));
    });

    test('24H guard rolls correctly across year boundaries', () {
      final guard = PracticeGuard.fromEntry(entry('urg-24h', '2026-12-31'));
      expect(guard, isNotNull);
      expect(guard!.start, DateTime(2026, 12, 31, 8));
      expect(guard.end, DateTime(2027, 1, 1, 8));
    });

    test('includes disciplinary emergency guards in Practice', () {
      final guard = PracticeGuard.current(
        entries: [entry('urg-nuit', '2026-10-01', isDisciplinary: true)],
        user: user,
        now: DateTime(2026, 10, 1, 23, 3),
      );
      expect(guard, isNotNull);
      expect(guard!.isDisciplinary, isTrue);
    });

    test('night guard is inactive before 20:00 start date and from 08:00 next day', () {
      final night = entry('urg-nuit', '2026-10-01');
      expect(
        PracticeGuard.current(entries: [night], user: user, now: DateTime(2026, 10, 1, 19, 59)),
        isNull,
      );
      expect(
        PracticeGuard.current(entries: [night], user: user, now: DateTime(2026, 10, 2, 8)),
        isNull,
      );
    });

    test('ignores non emergency guards', () {
      final guard = PracticeGuard.current(
        entries: [entry('service-jour', '2026-10-15')],
        user: user,
        now: DateTime(2026, 10, 15, 10),
      );
      expect(guard, isNull);
    });
  });

  group('PracticeCase validation and XP', () {
    PracticeCase value({
      String reason = '',
      String interrogatoire = '',
      String history = '',
      String exam = '',
      String assessment = '',
      String plan = '',
      bool draft = false,
    }) => PracticeCase(
          userId: 'user-1',
          guardId: 'guard-1',
          guardDate: '2026-09-29',
          guardShiftId: 'urg-nuit',
          clientId: 'client-1',
          patientNumber: 1,
          consultationReason: reason,
          interrogatoire: interrogatoire,
          illnessHistory: history,
          clinicalExam: exam,
          assessment: assessment,
          plan: plan,
          isDraft: draft,
        );

    test('does not validate a simple New patient tap', () {
      expect(value(reason: 'Douleur abdominale').isValid, isFalse);
      expect(value(reason: 'Douleur abdominale').xp, 0);
    });

    test('validates reason plus one clinical section', () {
      final item = value(reason: 'Douleur abdominale', exam: 'Abdomen souple.');
      expect(item.isValid, isTrue);
      expect(item.isComplete, isFalse);
      expect(item.xp, 10);
    });

    test('complete structured observation receives only documentation bonus', () {
      final item = value(
        reason: 'Dyspnée',
        history: 'Depuis 24 heures.',
        exam: 'SpO2 documentée.',
        assessment: 'Synthèse clinique.',
        plan: 'Conduite à tenir documentée.',
      );
      expect(item.isComplete, isTrue);
      expect(item.xp, 12);
    });

    test('drafts never count XP', () {
      final item = value(reason: 'Traumatisme', exam: 'Examen documenté.', draft: true);
      expect(item.isValid, isTrue);
      expect(item.xp, 0);
    });
  });

  test('level progression remains deterministic', () {
    expect(practiceLevelForXp(0).number, 1);
    expect(practiceLevelForXp(100).number, 2);
    expect(practiceLevelForXp(2300).number, 7);
  });
}
