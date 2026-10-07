import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/app_user.dart';
import 'package:huim6_planning/services/official_roster_consensus_service.dart';
import 'package:huim6_planning/services/official_roster_identity_service.dart';

AppUser _doctor(String id, String first, String last) => AppUser(
      id: id,
      nom: last,
      prenom: first,
      phone: '06$id',
      passwordHash: '',
      passwordSalt: '',
      service: 'Imagerie médicale',
      grade: MedicalGrade.junior,
      hospital: 'Test Hospital',
    );

OfficialRosterVisualDoctor _visual(
  String first,
  String last, {
  double confidence = .99,
}) =>
    OfficialRosterVisualDoctor(
      firstName: first,
      lastName: last,
      fullName: '$first $last',
      confidence: confidence,
    );

void main() {
  group('identity matching', () {
    test('normalization is conservative and typography-only', () {
      expect(
        OfficialRosterIdentityService.normalizeConservative(
          "  Él-Amrani  O’Neil ",
        ),
        'el amrani o neil',
      );
      expect(
        OfficialRosterIdentityService.normalizeConservative('Mohamed'),
        isNot(
          OfficialRosterIdentityService.normalizeConservative('Mohammed'),
        ),
      );
    });

    test('requires exact first name AND last name for automatic attribution', () {
      final profiles = [
        _doctor('1', 'Mohammed', 'El Amrani'),
      ];
      final exact = OfficialRosterIdentityService.resolve(
        firstName: 'Mohammed',
        lastName: 'El-Amrani',
        profiles: profiles,
      );
      expect(exact.profileId, '1');
      expect(exact.ambiguous, isFalse);

      final fuzzy = OfficialRosterIdentityService.resolve(
        firstName: 'Mohamed',
        lastName: 'El Amrani',
        profiles: profiles,
      );
      expect(fuzzy.profileId, isNull);
      expect(fuzzy.suggestions, isNotEmpty);
      expect(fuzzy.suggestions.first.exact, isFalse);
    });

    test('homonymy blocks automatic attribution', () {
      final profiles = [
        _doctor('1', 'Aymen', 'Akdim'),
        _doctor('2', 'Aymen', 'Akdim'),
      ];
      final result = OfficialRosterIdentityService.resolve(
        firstName: 'Aymen',
        lastName: 'Akdim',
        profiles: profiles,
      );
      expect(result.profileId, isNull);
      expect(result.ambiguous, isTrue);
      expect(result.suggestions, hasLength(2));
    });

    test('first name or last name alone never auto-assigns', () {
      final profiles = [_doctor('1', 'Aymen', 'Akdim')];
      expect(
        OfficialRosterIdentityService.resolve(
          firstName: 'Aymen',
          lastName: '',
          profiles: profiles,
        ).profileId,
        isNull,
      );
      expect(
        OfficialRosterIdentityService.resolve(
          firstName: '',
          lastName: 'Akdim',
          profiles: profiles,
        ).profileId,
        isNull,
      );
    });
  });

  group('A/B/C consensus', () {
    final completeA = const [
      OfficialRosterLocalCell(
        date: '2026-10-01',
        shift: 'urg-jour',
        text: 'Aymen Akdim',
      ),
      OfficialRosterLocalCell(
        date: '2026-10-01',
        shift: 'urg-nuit',
        text: 'Hamza El Moudden',
      ),
      OfficialRosterLocalCell(
        date: '2026-10-02',
        shift: 'urg-24h',
        text: 'Marwa Oukkas',
      ),
    ];

    test('A=B with complete structure is GREEN and does not request C', () {
      final b = OfficialRosterVisualRead(
        confidence: .99,
        rows: [
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-jour',
            doctors: [_visual('Aymen', 'Akdim')],
          ),
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-nuit',
            doctors: [_visual('Hamza', 'El Moudden')],
          ),
          OfficialRosterVisualRow(
            date: '2026-10-02',
            shift: 'urg-24h',
            doctors: [_visual('Marwa', 'Oukkas')],
          ),
        ],
      );
      final decision = OfficialRosterConsensusService.evaluate(
        localA: completeA,
        visualB: b,
      );
      expect(decision.status, OfficialRosterConsensusStatus.green);
      expect(decision.requiresC, isFalse);
      expect(decision.publishable, isTrue);
    });

    test('A/B mismatch requests C', () {
      final b = OfficialRosterVisualRead(
        confidence: .99,
        rows: [
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-jour',
            doctors: [_visual('Ayoub', 'Akdim')],
          ),
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-nuit',
            doctors: [_visual('Hamza', 'El Moudden')],
          ),
          OfficialRosterVisualRow(
            date: '2026-10-02',
            shift: 'urg-24h',
            doctors: [_visual('Marwa', 'Oukkas')],
          ),
        ],
      );
      final decision = OfficialRosterConsensusService.evaluate(
        localA: completeA,
        visualB: b,
      );
      expect(decision.status, OfficialRosterConsensusStatus.red);
      expect(decision.requiresC, isTrue);
      expect(
        decision.conflicts.any((c) => c.code == 'identity_mismatch'),
        isTrue,
      );
    });

    test('C resolves A/B disagreement to ORANGE when C confirms B', () {
      OfficialRosterVisualRead read(String first) => OfficialRosterVisualRead(
            confidence: .99,
            rows: [
              OfficialRosterVisualRow(
                date: '2026-10-01',
                shift: 'urg-jour',
                doctors: [_visual(first, 'Akdim')],
              ),
              OfficialRosterVisualRow(
                date: '2026-10-01',
                shift: 'urg-nuit',
                doctors: [_visual('Hamza', 'El Moudden')],
              ),
              OfficialRosterVisualRow(
                date: '2026-10-02',
                shift: 'urg-24h',
                doctors: [_visual('Marwa', 'Oukkas')],
              ),
            ],
          );

      final b = read('Ayoub');
      final c = read('Ayoub');
      final decision = OfficialRosterConsensusService.evaluate(
        localA: completeA,
        visualB: b,
        visualC: c,
      );
      expect(decision.status, OfficialRosterConsensusStatus.orange);
      expect(decision.publishable, isTrue);
    });

    test('persistent disagreement after C is RED', () {
      OfficialRosterVisualRead read(String first) => OfficialRosterVisualRead(
            confidence: .99,
            rows: [
              OfficialRosterVisualRow(
                date: '2026-10-01',
                shift: 'urg-jour',
                doctors: [_visual(first, 'Akdim')],
              ),
              OfficialRosterVisualRow(
                date: '2026-10-01',
                shift: 'urg-nuit',
                doctors: [_visual('Hamza', 'El Moudden')],
              ),
              OfficialRosterVisualRow(
                date: '2026-10-02',
                shift: 'urg-24h',
                doctors: [_visual('Marwa', 'Oukkas')],
              ),
            ],
          );

      final decision = OfficialRosterConsensusService.evaluate(
        localA: completeA,
        visualB: read('Ayoub'),
        visualC: read('Yassine'),
      );
      expect(decision.status, OfficialRosterConsensusStatus.red);
      expect(decision.publishable, isFalse);
    });

    test('identical visual reads cannot hide an incomplete month', () {
      final incompleteA = const [
        OfficialRosterLocalCell(
          date: '2026-10-01',
          shift: 'urg-jour',
          text: 'Aymen Akdim',
        ),
      ];
      final b = OfficialRosterVisualRead(
        confidence: .99,
        rows: [
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-jour',
            doctors: [_visual('Aymen', 'Akdim')],
          ),
        ],
      );
      final decision = OfficialRosterConsensusService.evaluate(
        localA: incompleteA,
        visualB: b,
      );
      expect(decision.status, OfficialRosterConsensusStatus.red);
      expect(decision.validationErrors, isNotEmpty);
    });

    test('low per-doctor confidence never silently publishes', () {
      final b = OfficialRosterVisualRead(
        confidence: .99,
        rows: [
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-jour',
            doctors: [_visual('Aymen', 'Akdim', confidence: .70)],
          ),
          OfficialRosterVisualRow(
            date: '2026-10-01',
            shift: 'urg-nuit',
            doctors: [_visual('Hamza', 'El Moudden')],
          ),
          OfficialRosterVisualRow(
            date: '2026-10-02',
            shift: 'urg-24h',
            doctors: [_visual('Marwa', 'Oukkas')],
          ),
        ],
      );
      final decision = OfficialRosterConsensusService.evaluate(
        localA: completeA,
        visualB: b,
      );
      expect(decision.publishable, isFalse);
      expect(decision.requiresC, isTrue);
    });
  });
}
