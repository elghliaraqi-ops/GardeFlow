import '../models/app_user.dart';

class OfficialDoctorCandidate {
  final AppUser profile;
  final double score;
  final bool exact;

  const OfficialDoctorCandidate({
    required this.profile,
    required this.score,
    required this.exact,
  });
}

class OfficialDoctorResolution {
  final String? profileId;
  final bool ambiguous;
  final List<OfficialDoctorCandidate> suggestions;

  const OfficialDoctorResolution({
    required this.profileId,
    required this.ambiguous,
    required this.suggestions,
  });

  bool get matched =>
      profileId != null && profileId!.isNotEmpty && !ambiguous;
}

class OfficialRosterIdentityService {
  OfficialRosterIdentityService._();

  static String normalizeConservative(String input) {
    var value = input.toLowerCase().trim();
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'œ': 'oe',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
      'æ': 'ae',
      '’': ' ',
      "'": ' ',
      '-': ' ',
      '–': ' ',
      '—': ' ',
    };
    for (final entry in replacements.entries) {
      value = value.replaceAll(entry.key, entry.value);
    }
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String identityKey({
    required String firstName,
    required String lastName,
  }) {
    return '${normalizeConservative(firstName)}|'
        '${normalizeConservative(lastName)}';
  }

  /// Automatic attribution is deliberately strict:
  /// - first name AND last name are mandatory;
  /// - both must match after conservative typography normalization;
  /// - more than one exact candidate blocks attribution.
  ///
  /// Approximate matching is returned only as suggestions and never decides.
  static OfficialDoctorResolution resolve({
    required String firstName,
    required String lastName,
    required List<AppUser> profiles,
    String? persistentProfileId,
  }) {
    final first = normalizeConservative(firstName);
    final last = normalizeConservative(lastName);
    if (first.isEmpty || last.isEmpty) {
      return OfficialDoctorResolution(
        profileId: null,
        ambiguous: false,
        suggestions: _suggest(first, last, profiles),
      );
    }

    if (persistentProfileId != null && persistentProfileId.isNotEmpty) {
      final linked = profiles
          .where((profile) => profile.id == persistentProfileId)
          .toList(growable: false);
      if (linked.length == 1) {
        return OfficialDoctorResolution(
          profileId: linked.single.id,
          ambiguous: false,
          suggestions: [
            OfficialDoctorCandidate(
              profile: linked.single,
              score: 1,
              exact: true,
            ),
          ],
        );
      }
    }

    final exact = profiles.where((profile) {
      return normalizeConservative(profile.prenom) == first &&
          normalizeConservative(profile.nom) == last;
    }).toList(growable: false);

    if (exact.length == 1) {
      return OfficialDoctorResolution(
        profileId: exact.single.id,
        ambiguous: false,
        suggestions: [
          OfficialDoctorCandidate(
            profile: exact.single,
            score: 1,
            exact: true,
          ),
        ],
      );
    }

    if (exact.length > 1) {
      return OfficialDoctorResolution(
        profileId: null,
        ambiguous: true,
        suggestions: exact
            .map(
              (profile) => OfficialDoctorCandidate(
                profile: profile,
                score: 1,
                exact: true,
              ),
            )
            .toList(growable: false),
      );
    }

    return OfficialDoctorResolution(
      profileId: null,
      ambiguous: false,
      suggestions: _suggest(first, last, profiles),
    );
  }

  static List<OfficialDoctorCandidate> _suggest(
    String first,
    String last,
    List<AppUser> profiles,
  ) {
    if (first.isEmpty && last.isEmpty) return const [];
    final candidates = <OfficialDoctorCandidate>[];
    for (final profile in profiles) {
      final profileFirst = normalizeConservative(profile.prenom);
      final profileLast = normalizeConservative(profile.nom);
      if (profileFirst.isEmpty || profileLast.isEmpty) continue;

      final firstScore = _similarity(first, profileFirst);
      final lastScore = _similarity(last, profileLast);
      final score = first.isEmpty
          ? lastScore
          : last.isEmpty
              ? firstScore
              : (firstScore + lastScore) / 2;

      if (score >= 0.72) {
        candidates.add(
          OfficialDoctorCandidate(
            profile: profile,
            score: score,
            exact: false,
          ),
        );
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.take(5).toList(growable: false);
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1;
    if (a.isEmpty || b.isEmpty) return 0;
    final distance = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return maxLen == 0 ? 1 : 1 - distance / maxLen;
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final insertion = current[j - 1] + 1;
        final deletion = previous[j] + 1;
        final substitution = previous[j - 1] +
            (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1);
        current[j] = insertion < deletion
            ? (insertion < substitution ? insertion : substitution)
            : (deletion < substitution ? deletion : substitution);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
