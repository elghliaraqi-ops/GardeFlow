import '../models/app_user.dart';

/// Référentiel historique des promotions actuellement connues.
///
/// Ces listes servent uniquement à compléter la promotion des comptes existants
/// issus du PDF/référentiel transmis. Elles ne définissent pas la règle métier
/// des échanges : la première année est toujours la promotion active la plus
/// récente, quelle que soit sa valeur (Promo 7 aujourd'hui, Promo 8 demain, etc.).
class InternPromotions {
  InternPromotions._();

  static String _normalize(String value) {
    var s = value.toLowerCase().trim();
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'œ': 'oe',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
      'æ': 'ae', '’': ' ', "'": ' ', '-': ' ',
    };
    for (final e in replacements.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _key(String nom, String prenom) => _normalize('$nom $prenom');

  static const Set<String> _promo5 = {
    'najid saad', 'saad najid',
  };

  static const Set<String> _promo6 = {
    'aamer anas', 'abderrahmane elferdaous', 'adil lina', 'ahlsidimouloud aicha',
    'akdim aymen', 'amchaarou hamza', 'araqi el ghali', 'araqui houssaini elghali', 'araqui houssaini el ghali', 'belhaj anas',
    'bennani simo', 'bennour ghita', 'benzekri ines', 'bouhmouch ines',
    'bourkia wail', 'bouziane zineb', 'drifi salma', 'driouech selma',
    'el baz daoud', 'ezzine khadija', 'fassy fehry reda', 'hamich omar',
    'imakor younes', 'imane norri', 'ines khairi', 'iziraren yasmine',
    'khaled hajar', 'laghdaf alia', 'latif idrissi fairouz', 'maarouf aala',
    'maryam elbardi', 'mellak omar', 'mourad ismail', 'moussa yahya',
    'nouhaila aarab',
    'nyar malak', 'qossaim safaa', 'sahel ibtihal', 'sekkat kenza',
    'serir ahmed', 'tary yasmine', 'tlem aya', 'trabelsi salma',
    'wiame khalifi', 'yazid marfoq', 'zaghrari dahmane',
    'zaghrari mohammed dahmane', 'zaghrari mohamed dahmane',
    'mohammed dahmane zaghrari', 'mohamed dahmane zaghrari',
    'dahmane mohammed zaghrari', 'dahmane mohamed zaghrari',
    'zahid mohamed amine',
  };

  static const Set<String> _promo7 = {
    'abbassi amine', 'ahjyage rim', 'albab salma', 'atassi salma', 'atassi souha',
    'attou ilyas', 'bahaddi marwa', 'bakertit hiba', 'bargache ghita', 'benakkouch reda',
    'benaoda tlemcani mehdi', 'benattahellah mehdi', 'benhalima ines', 'bennis ines',
    'benomar meryem', 'benoufir salim', 'benzakour amine alia', 'berhili meryam',
    'berraho aya', 'bettach rania', 'bouchikhi lina', 'bourouda mounia', 'boutahri afaf',
    'cabrane oumnia', 'chadni manal', 'chamiti maria', 'channaoui imane', 'chaouki khawla',
    'cheikh manal', 'cherkaoui meryem', 'choklati aya', 'chraibi hamd', 'dami rime',
    'dlimi nouha', 'douazi kenza', 'douni driss', 'el bardai badr', 'el benna meriem',
    'el eulj mohamed', 'el maazi ines', 'el merzougui yasmine', 'el mouden hamza',
    'ennassiri ghaliya', 'fatnane wissal', 'fenjiro rime', 'fetich ahmed',
    'filali el garch lina', 'guessous imane', 'hadadia meryam', 'hanafi nassima',
    'harout salma', 'jebri ikrame', 'joundy jannate', 'khadraoui nour', 'khairi yasmine',
    'kouhen yassine', 'laabidi zakariae', 'laaroussi oumaima', 'lahroussi aymen',
    'lasry youssef', 'lefriyekh omar', 'lyamani rime', 'lyoubi idrissi soraya',
    'maaden kaoutar', 'madi yazid', 'mahaouchi ayoub', 'mahboub chama', 'majidi zineb',
    'moussa aya', 'najah amine', 'nasri wiam', 'nasrollah fatima zahra', 'ouakani mohamed',
    'oukkas marwa', 'oulderrachid lalla hind', 'ouliou aya', 'oumary basma',
    'outaleb nour alhouda', 'raissouni ghita', 'raji loubna', 'rouissi maryem',
    'sentissi badr eddine', 'serghat rania', 'tajri anas', 'youssefi yasmine', 'zahir ghita',
  };

  static int? numberForNames(String nom, String prenom) {
    final key = _key(nom, prenom);
    if (_promo7.contains(key)) return 7;
    if (_promo6.contains(key)) return 6;
    if (_promo5.contains(key)) return 5;

    final reverse = _key(prenom, nom);
    if (_promo7.contains(reverse)) return 7;
    if (_promo6.contains(reverse)) return 6;
    if (_promo5.contains(reverse)) return 5;
    return null;
  }

  static int? numberFor(AppUser? user) => user == null
      ? null
      : user.promotionNumber ?? numberForNames(user.nom, user.prenom);

  static int? highestPromotion(Iterable<AppUser> users) {
    int? result;
    for (final user in users) {
      if (user.grade != MedicalGrade.junior || user.accountStatus != AccountStatus.active) continue;
      final promotion = numberFor(user);
      if (promotion == null) continue;
      if (result == null || promotion > result) result = promotion;
    }
    return result;
  }

  /// Calcule l'année d'internat relativement à la promotion actuellement en
  /// première année. Exemple : si la Promo 8 est la plus récente, Promo 8 =
  /// 1re année, Promo 7 = 2e année, Promo 6 = 3e année, etc.
  static int? trainingYearForPromotion(
    int? promo, {
    required int firstYearPromotion,
  }) {
    if (promo == null || promo < 1 || firstYearPromotion < 1 || promo > firstYearPromotion) {
      return null;
    }
    return firstYearPromotion - promo + 1;
  }

  static String? yearLabelForPromotion(
    int? promo, {
    required int firstYearPromotion,
  }) {
    final year = trainingYearForPromotion(
      promo,
      firstYearPromotion: firstYearPromotion,
    );
    if (year == null) return null;
    return year == 1 ? '1re année' : '${year}e année';
  }

  static String? labelFor(
    AppUser? user, {
    required int firstYearPromotion,
  }) {
    final promo = numberFor(user);
    final year = yearLabelForPromotion(
      promo,
      firstYearPromotion: firstYearPromotion,
    );
    if (promo == null || year == null) return null;
    return '$year · Promo $promo';
  }

  /// La promotion la plus récente (= première année) ne peut transférer ou
  /// échanger qu'avec elle-même. Toutes les promotions antérieures peuvent
  /// échanger/transférer entre elles.
  static bool crossYearBlocked(
    AppUser? a,
    AppUser? b, {
    required int firstYearPromotion,
  }) {
    final pa = numberFor(a);
    final pb = numberFor(b);
    if (pa == null || pb == null || pa == pb) return false;

    // Défense contre un état local momentanément en retard par rapport au
    // serveur : si un profil porte déjà une promo plus récente, elle devient
    // immédiatement la référence pour cette comparaison.
    var effectiveFirstYear = firstYearPromotion;
    if (pa > effectiveFirstYear) effectiveFirstYear = pa;
    if (pb > effectiveFirstYear) effectiveFirstYear = pb;

    return pa == effectiveFirstYear || pb == effectiveFirstYear;
  }

  /// Alias du planning officiel quand le compte contient plusieurs prénoms.
  /// Le compte « Mohammed Dahmane Zaghrari » doit reconnaître « Dahmane Zaghrari ».
  static Set<String> officialRosterAliasesFor(AppUser user) {
    final key = _key(user.nom, user.prenom);
    final reverse = _key(user.prenom, user.nom);
    const zaghrariKeys = <String>{
      'zaghrari mohammed dahmane',
      'zaghrari mohamed dahmane',
      'mohammed dahmane zaghrari',
      'mohamed dahmane zaghrari',
      'dahmane mohammed zaghrari',
      'dahmane mohamed zaghrari',
    };
    if (zaghrariKeys.contains(key) || zaghrariKeys.contains(reverse)) {
      return const <String>{'dahmane zaghrari', 'zaghrari dahmane'};
    }
    return const <String>{};
  }
}
