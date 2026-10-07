import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/app_user.dart';
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
}
