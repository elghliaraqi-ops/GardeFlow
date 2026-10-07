import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/app_user.dart';
import 'package:huim6_planning/models/official_roster_guard.dart';
import 'package:huim6_planning/services/official_roster_verified_read_service.dart';

AppUser doctor(String id, String nom, String prenom) => AppUser(
      id: id,
      nom: nom,
      prenom: prenom,
      phone: '0600000000',
      passwordHash: '',
      passwordSalt: '',
      service: 'Imagerie médicale',
      grade: MedicalGrade.junior,
      hospital: 'Test Hospital',
    );

void main() {
  test('verified read keeps every doctor in a multi-name cell', () {
    final profiles = [
      doctor('a', 'AKDIM', 'Aymen'),
      doctor('b', 'EL MOUDDEN', 'Hamza'),
    ];
    final result = OfficialRosterVerifiedReadService.fromExtraction(
      extraction: {
        'verified': true,
        'confidence': 0.98,
        'warnings': <String>[],
        'rows': [
          {
            'date': '2026-10-07',
            'shift': 'urg-jour',
            'names': ['Aymen Akdim', 'Hamza El Moudden'],
            'red_names': <String>[],
          },
          {
            'date': '2026-10-07',
            'shift': 'urg-nuit',
            'names': <String>[],
            'red_names': <String>[],
          },
        ],
      },
      hospital: 'Test Hospital',
      profiles: profiles,
    );

    expect(result.isComplete, isTrue);
    expect(result.assignments.length, 2);
    expect(
      result.assignments.map((a) => a.profileId).toSet(),
      {'a', 'b'},
    );
  });

  test('same doctor on day and night becomes one 24h assignment', () {
    final profiles = [doctor('a', 'AKDIM', 'Aymen')];
    final result = OfficialRosterVerifiedReadService.fromExtraction(
      extraction: {
        'verified': true,
        'confidence': 0.99,
        'warnings': <String>[],
        'rows': [
          {
            'date': '2026-10-08',
            'shift': 'urg-jour',
            'names': ['Aymen Akdim'],
            'red_names': <String>[],
          },
          {
            'date': '2026-10-08',
            'shift': 'urg-nuit',
            'names': ['Aymen Akdim'],
            'red_names': <String>[],
          },
        ],
      },
      hospital: 'Test Hospital',
      profiles: profiles,
    );

    expect(result.isComplete, isTrue);
    expect(result.assignments, hasLength(1));
    expect(result.assignments.single.shiftId, 'urg-24h');
  });

  test('unverified visual read is fail closed', () {
    final result = OfficialRosterVerifiedReadService.fromExtraction(
      extraction: {
        'verified': false,
        'confidence': 0.65,
        'warnings': <String>[],
        'rows': <Map<String, dynamic>>[],
      },
      hospital: 'Test Hospital',
      profiles: [doctor('a', 'AKDIM', 'Aymen')],
    );

    expect(result.isComplete, isFalse);
    expect(result.validationErrors, isNotEmpty);
  });

  test('R6 keeps an unregistered doctor as an official guard', () {
    final result = OfficialRosterVerifiedReadService.fromExtraction(
      extraction: {
        'verified': true,
        'parser_revision': 'v12.0.2-r6',
        'status': 'green',
        'confidence': 0.99,
        'validation_errors': <String>[],
        'rows': [
          {
            'date': '2026-10-09',
            'shift': 'urg-jour',
            'doctors': [
              {
                'first_name': 'Marwa',
                'last_name': 'Oukkas',
                'full_name': 'Marwa Oukkas',
                'confidence': 0.99,
              },
            ],
            'red_names': <String>[],
            'page_number': 1,
            'zone': '09 octobre / Jour',
          },
          {
            'date': '2026-10-09',
            'shift': 'urg-nuit',
            'doctors': <Map<String, dynamic>>[],
            'red_names': <String>[],
            'page_number': 1,
            'zone': '09 octobre / Nuit',
          },
        ],
      },
      hospital: 'Test Hospital',
      profiles: [doctor('a', 'AKDIM', 'Aymen')],
    );

    expect(result.isComplete, isTrue);
    expect(result.assignments, isEmpty);
    expect(result.officialGuards, hasLength(1));
    expect(result.officialGuards.single.displayName, 'Marwa Oukkas');
    expect(
      result.officialGuards.single.matchStatus,
      OfficialDoctorMatchStatus.unregistered,
    );
    expect(
      result.unmatchedCells.single['reason'],
      'doctor_not_registered',
    );
  });

  test('R6 homonyms remain ambiguous and never auto-assign', () {
    final profiles = [
      doctor('a', 'AKDIM', 'Aymen'),
      doctor('b', 'AKDIM', 'Aymen'),
    ];
    final result = OfficialRosterVerifiedReadService.fromExtraction(
      extraction: {
        'verified': true,
        'parser_revision': 'v12.0.2-r6',
        'status': 'green',
        'confidence': 0.99,
        'validation_errors': <String>[],
        'rows': [
          {
            'date': '2026-10-10',
            'shift': 'urg-24h',
            'doctors': [
              {
                'first_name': 'Aymen',
                'last_name': 'Akdim',
                'full_name': 'Aymen Akdim',
                'confidence': 0.99,
              },
            ],
            'red_names': <String>[],
            'page_number': 1,
            'zone': '10 octobre / 24H',
          },
        ],
      },
      hospital: 'Test Hospital',
      profiles: profiles,
    );

    expect(result.isComplete, isTrue);
    expect(result.assignments, isEmpty);
    expect(result.officialGuards, hasLength(1));
    expect(
      result.officialGuards.single.matchStatus,
      OfficialDoctorMatchStatus.ambiguous,
    );
    expect(
      result.unmatchedCells.single['reason'],
      'ambiguous_identity',
    );
    expect(
      (result.unmatchedCells.single['candidates'] as List).length,
      2,
    );
  });

  test('R6 fuzzy candidate is suggested but never assigned', () {
    final result = OfficialRosterVerifiedReadService.fromExtraction(
      extraction: {
        'verified': true,
        'parser_revision': 'v12.0.2-r6',
        'status': 'green',
        'confidence': 0.99,
        'validation_errors': <String>[],
        'rows': [
          {
            'date': '2026-10-11',
            'shift': 'urg-24h',
            'doctors': [
              {
                'first_name': 'Mohamed',
                'last_name': 'El Amrani',
                'full_name': 'Mohamed El Amrani',
                'confidence': 0.99,
              },
            ],
            'red_names': <String>[],
            'page_number': 1,
            'zone': '11 octobre / 24H',
          },
        ],
      },
      hospital: 'Test Hospital',
      profiles: [doctor('a', 'El Amrani', 'Mohammed')],
    );

    expect(result.isComplete, isTrue);
    expect(result.assignments, isEmpty);
    expect(
      result.officialGuards.single.matchStatus,
      OfficialDoctorMatchStatus.manualReview,
    );
    expect(
      result.unmatchedCells.single['reason'],
      'potential_identity_requires_admin',
    );
  });

}
