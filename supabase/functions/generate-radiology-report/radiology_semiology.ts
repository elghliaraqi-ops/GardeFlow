/**
 * Symptom-oriented CT semiology, not diagnostic assertions. Each entry asks
 * whether a discriminating image sign was ACTUALLY observed. The reporting
 * contract only emits negative sentences after explicit physician review.
 *
 * Educational basis: Radiology Assistant "Appendicitis and Mimics",
 * "Practical approach to Acute Abdomen"; ACR Appropriateness Criteria
 * Right Lower Quadrant Pain and Acute Pelvic Pain.
 * Remote reference-image queries contain no patient information.
 */
export type SemiologyEntry = [
  section: string, question: string, negative: string,
  definition: string, criteria: string, imageQuery?: string,
];
export type AnatomicSex = 'female'|'male'|'other'|'unknown';

export function normalizedClinical(value: string): string {
  return value.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().replace(/[’']/g, ' ');
}
const fid = /fosse iliaque droite|\bfid\b|right lower quadrant|\brlq\b|right iliac fossa|quadrant inferieur droit/;
const lig = /fosse iliaque gauche|\bfig\b|left lower quadrant|\bllq\b|quadrant inferieur gauche/;
const flank = /colique nephretique|douleur (du )?flanc|douleur lombaire|lombalgie.*(aigue|febr)|renal colic|flank pain/;
const ruq = /hypochondre droit|\bhd\b|right upper quadrant|quadrant superieur droit/;
const abd = /abdom|abdo|ventre|peritonite|abdomen aigu/;
const pelvic = /douleur pelvien|douleur pelvi|douleur hypogastr|pelvic pain|douleur sus.pubien/;
const isCt = (s: string) => /\b(tdm|scanner|ct|tomodensitometrie|angio.tdm)\b/.test(s);
const isAbdominoPelvic = (s: string) => /abdom|pelv|bassin|\btap\b|uro|rein/.test(s);
const isThoracic = (s: string) => /thorac|thorax|pulmon|poumon|\btap\b/.test(s);
const isBrain = (s: string) => /cerebr|encephal|cranien|cerveau|tete|brain/.test(s);
const appendix: SemiologyEntry[] = [
  ['Indication · Appendice','Appendice dilaté avec épaississement/rehaussement pariétal ?',
    'Pas de dilatation appendiculaire associée à un épaississement pariétal sur les segments correctement identifiés.',
    'Appendicite : appendice augmenté de calibre ET signes pariétaux/périappendiculaires. Un diamètre > 6 mm isolé ne suffit pas.',
    'Identifier l’appendice depuis la base cæcale ; mesurer calibre externe, paroi, contenu, rehaussement si injecté. Si non identifiable : non évaluable, ne pas conclure à un appendice normal.',
    'CT acute appendicitis enlarged appendix wall thickening'],
  ['Indication · Appendice','Infiltration de la graisse périappendiculaire centrée sur l’appendice ?',
    'Pas d’infiltration de la graisse périappendiculaire sur les zones évaluables.',
    'Le centre de l’inflammation permet de différencier appendicite, diverticulite cæcale et appendagite épiploïque.',
    'Apprécier infiltration graisseuse, hyperhémie mésentérique, réaction cæcale, fascia et épicentre ; corréler à l’appendice.',
    'CT periappendiceal fat stranding appendicitis'],
  ['Indication · Appendice','Appendicolithe, liquide intraluminal ou collection appendiculaire ?',
    'Pas d’appendicolithe ni de distension liquidienne évidente sur l’appendice exploré.',
    'L’appendicolithe peut accompagner une appendicite, sans suffire à confirmer son caractère aigu.',
    'Chercher calcification luminale, distension liquide et inflammation environnante ; noter taille et topographie.',
    'CT appendicolith appendiceal obstruction'],
  ['Indication · Appendice','Perforation, plastron ou abcès périappendiculaire ?',
    'Pas de collection périappendiculaire ni de gaz extra-digestif local identifié.',
    'Complications inflammatoires à distinguer d’une appendicite non compliquée.',
    'Rechercher collection à paroi rehaussée, bulles extraluminales, phlegmon, défect pariétal et iléus voisin.',
    'CT perforated appendicitis appendiceal abscess'],
  ['Indication · Diagnostic différentiel digestif','Diverticule cæcal/colique droit inflammatoire, plutôt qu’appendicite ?',
    'Pas de diverticule inflammatoire évident au niveau du côlon droit exploré.',
    'Diverticulite cæcale : inflammation centrée sur un diverticule colique, avec appendice distinct.',
    'Rechercher diverticule, épaississement local du cæcum/ascendant, infiltration péricolique ; localiser l’épicentre.',
    'CT right cecal diverticulitis appendicitis mimic'],
  ['Indication · Diagnostic différentiel digestif','Iléite terminale ou épaississement iléocæcal (infection ou Crohn) ?',
    'Pas d’épaississement iléo-cæcal inflammatoire évident sur les segments évalués.',
    'L’inflammation iléo-cæcale peut simuler une appendicite ; l’atteinte pariétale digestive et sa longueur orientent.',
    'Localisation iléale, longueur, stratification, hypervascularisation, graisse mésentérique, fistules/collections si visibles.',
    'CT terminal ileitis Crohn ileocecal inflammation'],
  ['Indication · Diagnostic différentiel digestif','Adénite mésentérique iléocæcale avec appendice non inflammatoire ?',
    'Pas de regroupement ganglionnaire mésentérique iléocæcal notable.',
    'Une adénite mésentérique peut provoquer une douleur de FID ; des ganglions isolés sont peu spécifiques.',
    'Mesurer le petit axe, décrire distribution en grappe et vérifier le statut de l’appendice sans le présumer normal.',
    'CT mesenteric adenitis right lower quadrant'],
  ['Indication · Graisse péritonéale','Appendagite épiploïque ou infarctus épiploïque en FID ?',
    'Pas de foyer graisseux péricolique focal avec anneau hyperdense ou masse épiploïque inflammatoire identifié.',
    'Appendagite : ovalaire juxtacolique à anneau hyperdense ; infarctus du grand épiploon : plage graisseuse souvent plus volumineuse.',
    'Définir siège graisseux, taille, anneau hyperdense, point central, rapports avec appendice et paroi du côlon.',
    'CT epiploic appendagitis omental infarction right lower quadrant'],
  ['Indication · Voies urinaires','Calcul urétéral distal droit avec ou sans dilatation urinaire ?',
    'Pas de calcul urétéral distal droit ni de dilatation sus-jacente visible.',
    'Une colique urétérale distale peut simuler une douleur appendiculaire.',
    'Suivre l’uretère droit vers la jonction urétérovésicale ; calcul visible, hydrouretère, hydronéphrose et infiltration périurétérale ; phase non injectée si disponible.',
    'CT distal right ureter stone hydronephrosis'],
];
const femalePelvis: SemiologyEntry[] = [
  ['Indication · Annexes','Augmentation de volume ovarien, œdème ou disposition anormale des annexes ?',
    'Pas d’augmentation ovarienne majeure ni d’anomalie annexielle morphologique évidente sur les structures individualisables.',
    'Torsion annexielle : ovaire augmenté de volume, œdème stromal, follicules périphériques ou pédicule tordu ; la TDM ne l’exclut pas.',
    'Évaluer latéralité, taille, position, stroma, pédicule tordu si visualisé, épanchement. Si suspicion clinique, échographie Doppler gynécologique urgente ; un Doppler normal ne suffit pas à exclure une torsion.',
    'CT ovarian torsion enlarged edematous ovary twisted pedicle'],
  ['Indication · Annexes','Kyste annexiel hémorragique ou rupture avec liquide pelvien hyperdense ?',
    'Pas de volumineux kyste annexiel compliqué ni d’hémopéritoine évident sur les segments évalués.',
    'Kyste hémorragique/rompu : contenu dense et parfois hémopéritoine ; certains kystes nécessitent une caractérisation échographique.',
    'Mesurer la lésion et son contenu, rechercher liquide dense dans Douglas, coagulum et éventuellement saignement actif si phase adaptée.',
    'CT ruptured ovarian hemorrhagic cyst hemoperitoneum'],
  ['Indication · Annexes','Dilatation tubaire, salpingite ou abcès tubo-ovarien suspect ?',
    'Pas de masse tubo-ovarienne complexe ni de collection annexielle évidente.',
    'Salpingite/abcès tubo-ovarien : processus tubaire ou annexiel complexe avec inflammation de la graisse pelvienne.',
    'Rechercher tube dilaté épaissi, collection cloisonnée, rehaussement périphérique si injection, infiltration péripelvienne ; confronter au contexte infectieux.',
    'CT tubo ovarian abscess pelvic inflammatory disease'],
  ['Indication · Annexes','Hémopéritoine ou masse annexielle pouvant nécessiter exclusion d’une grossesse extra-utérine ?',
    'Pas d’hémopéritoine abondant ou de masse annexielle évidente sur cette TDM ; une grossesse extra-utérine ne peut pas être exclue par cet examen.',
    'Chez une patiente susceptible d’être enceinte, la grossesse extra-utérine se recherche par β-hCG et échographie endovaginale, non par la seule TDM.',
    'Rechercher liquide libre hyperdense et masse annexielle visible ; ne jamais conclure « GEU exclue » sur TDM ; préciser statut de grossesse et nécessité d’évaluation dédiée.',
    'CT adnexal hemoperitoneum ectopic pregnancy ultrasound differentiation'],
];
const rightUpper: SemiologyEntry[] = [
  ['Indication · Voies biliaires','Vésicule distendue avec calcul, paroi épaissie ou graisse inflammatoire périvésiculaire ?',
    'Pas de signe TDM évident de complication inflammatoire vésiculaire.',
    'Cholécystite : distension, épaississement pariétal et inflammation environnante ; échographie souvent nécessaire si suspicion.',
    'Décrire calculs détectables, paroi, rehaussement si injecté, graisse, liquide périvésiculaire et limites de détection des calculs en TDM.',
    'CT acute cholecystitis gallbladder wall pericholecystic stranding'],
  ['Indication · Voies biliaires','Voies biliaires dilatées ou obstacle cholédocien visible ?',
    'Pas de dilatation biliaire significative évidente.',
    'Colique biliaire/obstacle cholédocien : rechercher une dilatation et une étiologie obstructive, sans présumer la visibilité de tous les calculs.',
    'Mesurer cholédoque, canaux intra-hépatiques, point d’arrêt et matériel hyperdense si visible ; âge et cholécystectomie modifient interprétation.',
    'CT common bile duct dilation choledocholithiasis'],
  ['Indication · Foie','Foyer hépatique inflammatoire, collection ou lésion focale douloureuse ?',
    'Pas de collection hépatique visible sur les phases acquises.',
    'Abcès hépatique et lésion focale peuvent entraîner douleur de l’hypochondre droit.',
    'Rechercher hypoatténuation, prise de contraste périphérique, gaz, œdème et autres lésions focales ; selon phase.',
    'CT liver abscess rim enhancement'],
];
const lowerLeft: SemiologyEntry[] = [
  ['Indication · Sigmoïde','Diverticule sigmoïdien inflammatoire avec infiltration de la graisse péricolique ?',
    'Pas de foyer diverticulaire sigmoïdien inflammatoire visible.',
    'Diverticulite sigmoïdienne : inflammation focale péridiverticulaire plutôt que colite diffuse.',
    'Chercher diverticule, épaississement mural, infiltration, collection ou air extraluminal.',
    'CT acute sigmoid diverticulitis pericolic stranding'],
  ['Indication · Sigmoïde','Épaississement colique étendu ou signes de colite/ischémie ?',
    'Pas d’épaississement colique gauche étendu évident sur les segments examinés.',
    'Colite infectieuse, inflammatoire ou ischémique : la longueur et la distribution sont discriminantes.',
    'Évaluer atteinte segmentaire, stratification, rehaussement si injecté, infiltration, pneumatoses et distribution vasculaire.',
    'CT left sided ischemic colitis bowel wall thickening'],
  ['Indication · Graisse péritonéale','Appendagite épiploïque juxta-sigmoïdienne ?',
    'Pas de lésion graisseuse juxta-sigmoïdienne à anneau hyperdense visible.',
    'L’appendagite épiploïque peut simuler une diverticulite avec moindre inflammation pariétale.',
    'Lésion ovale graisseuse péricolique, anneau hyperdense, graisse infiltrée et absence d’épaississement digestif majeur.',
    'CT epiploic appendagitis sigmoid hyperattenuating ring'],
];
const renal: SemiologyEntry[] = [
  ['Indication · Uretère','Calcul sur le trajet urétéral ou à la jonction urétéro-vésicale ?',
    'Pas de calcul urétéral identifié sur les segments évalués.',
    'Lithiase urétérale : foyer hyperdense endoluminal, parfois accompagné d’un syndrome obstructif.',
    'Suivre tout l’uretère, mesurer calcul/densité si phase sans injection ; ne pas appeler un phlébolithe « calcul » sans vérifier son trajet.',
    'CT ureterolithiasis ureter stone'],
  ['Indication · Obstacle urinaire','Dilatation pyélocalicielle/urétérale avec infiltration péri-rénale ?',
    'Pas de dilatation des cavités ni d’hydrouretère notable.',
    'Hydronéphrose : dilatation en amont d’un obstacle, parfois avec œdème péri-rénal.',
    'Distinguer bassinet extrarénal, identifier côté, degré de dilatation et obstacle visible.',
    'CT unilateral hydronephrosis perinephric stranding'],
  ['Indication · Infection urinaire','Hypodensités rénales triangulaires ou collection évoquant une pyélonéphrite ?',
    'Pas de lésion rénale inflammatoire focale ni de collection visible sur les phases évaluables.',
    'Pyélonéphrite : anomalie focale de néphrogramme ou infiltration ; TDM sans injection moins sensible.',
    'Rechercher néphrogramme strié, plage hypo-rehaussée, infiltration, abcès, gaz ; demander statut et phase injectée.',
    'CT acute pyelonephritis striated nephrogram'],
];
const acuteAbd: SemiologyEntry[] = [
  ['Indication · Occlusion','Anses digestives dilatées avec zone de transition ?',
    'Pas de dilatation digestive avec transition nette identifiée.',
    'Occlusion mécanique : dilatation en amont, obstacle/transition et affaissement en aval ; distinguer iléus.',
    'Mesurer calibre, distension, niveaux, zone de transition, hernie, bride suspecte, volvulus.',
    'CT small bowel obstruction transition point'],
  ['Indication · Souffrance digestive','Défaut de rehaussement pariétal, pneumatoses ou aéroportie ?',
    'Pas de pneumatoses ni de gaz portal visible ; l’ischémie ne peut être exclue sur ces seuls signes.',
    'L’ischémie digestive dépend de la perfusion, du rehaussement, de l’état vasculaire et des signes associés.',
    'Évaluer rehaussement si injection, congestion mésentérique, pneumatoses, gaz portal, épanchement ; ne pas écarter ischémie sans phase adaptée.',
    'CT bowel ischemia pneumatosis portal venous gas'],
  ['Indication · Péritoine','Pneumopéritoine, épanchement anormal ou collection abdominale ?',
    'Pas de pneumopéritoine, d’épanchement anormal ni de collection visible.',
    'Les signes péritonéaux peuvent orienter vers perforation, infection, hémorragie ou autre urgence.',
    'Vérifier petites bulles libres, liquide, graisse infiltrée, site d’une éventuelle perforation et abcès.',
    'CT pneumoperitoneum bowel perforation'],
];
const dyspnea: SemiologyEntry[] = [
  ['Indication · Parenchyme pulmonaire','Opacités alvéolaires focales ou bilatérales avec bronchogramme ?',
    'Pas de condensation alvéolaire individualisable sur les segments évalués.',
    'Consolidation infectieuse, atélectasie ou œdème peuvent partager une opacité ; la distribution et les signes associés comptent.',
    'Topographie, bronchogramme, perte de volume, bilatéralité et épanchement.',
    'chest CT consolidation pneumonia air bronchogram'],
  ['Indication · Interstitium','Verre dépoli ou épaississement septal avec distribution évocatrice d’œdème ?',
    'Pas d’association évidente de verre dépoli et épaississement septal diffus.',
    'Œdème interstitiel, infection, inflammation ou hémorragie alvéolaire se distinguent par distribution et contexte.',
    'Recherche verre dépoli, septa, cœur, épanchement, distribution péribronchovasculaire.',
    'chest CT pulmonary edema ground glass septal thickening'],
  ['Indication · Plèvre','Pneumothorax ou épanchement pleural expliquant la symptomatologie ?',
    'Pas de pneumothorax ni d’épanchement pleural notable.',
    'La plèvre peut expliquer une dyspnée aiguë ; quantifier l’extension et le retentissement.',
    'Ligne pleurale et air extra-pulmonaire ; liquide déclive et compression du parenchyme.',
    'CT pneumothorax pleural effusion'],
];
const vascularThorax: SemiologyEntry[] = [
  ['Indication · Angiographie thoracique','Défaut de remplissage des artères pulmonaires sur phase artérielle adéquate ?',
    'Pas de défaut de remplissage identifié des artères pulmonaires sur les segments techniquement évaluables.',
    'L’embolie pulmonaire nécessite une acquisition vasculaire pulmonaire appropriée ; ne pas l’exclure sur une TDM de routine.',
    'Défaut endoluminal dans l’arbre artériel opacifié, segment concerné, artefacts et qualité d’injection.',
    'CT pulmonary angiography pulmonary embolism filling defect'],
];
const brain: SemiologyEntry[] = [
  ['Indication · Parenchyme cérébral','Foyer hémorragique intracrânien ou sang méningé visible ?',
    'Pas d’hyperdensité hémorragique aiguë visible sur les territoires évalués en acquisition sans injection.',
    'Hémorragie intraparenchymateuse ou sous-arachnoïdienne : dépend de la phase et de la sensibilité du scanner.',
    'Hyperdensité spontanée, sillons/citernes, effet de masse ; ne pas exclure HSA par scanner tardif seul.',
    'non contrast brain CT subarachnoid hemorrhage'],
  ['Indication · Parenchyme cérébral','Signe précoce d’ischémie ou œdème focal ?',
    'Pas de dédifférenciation cortico-sous-corticale ni d’hypodensité vasculaire évidente.',
    'Un scanner cérébral normal précoce n’exclut pas l’ischémie aiguë.',
    'Ruban insulaire, effacement noyau lenticulaire, territoire, hyperdensité artérielle, ASPECTS si pertinent.',
    'brain CT early ischemic signs loss gray white differentiation'],
  ['Indication · Hydrocéphalie','Dilatation ventriculaire ou effet de masse avec engagement ?',
    'Pas d’hydrocéphalie ni de signe d’engagement visible.',
    'Une cause d’hypertension intracrânienne doit être recherchée devant céphalées ou signes neurologiques.',
    'Taille ventricules, effacement citernes et sillons, déplacement ligne médiane.',
    'CT hydrocephalus intracranial mass effect'],
];
export type SemiologyPlan = { matched: boolean; entries: SemiologyEntry[]; topics: string[] };
/**
 * Matches EVERY supplied symptom pattern, not merely the first. Unknown
 * indications are completed by a single Groq differential-planning request.
 */
export function indicationSemiology(args: {
  exam: string; region: string; indication: string; clinical?: string;
  technique?: string; sex?: AnatomicSex;
}): SemiologyPlan {
  const scope = normalizedClinical(args.exam + ' ' + args.region + ' ' + (args.technique || ''));
  const complaint = normalizedClinical(args.indication + ' ' + (args.clinical || ''));
  const sex = args.sex ?? 'unknown';
  const entries: SemiologyEntry[] = [], topics: string[] = [];
  const add = (topic: string, rows: SemiologyEntry[]) => {
    topics.push(topic);
    for (const row of rows) {
      if (!entries.some(x => x[1] === row[1])) entries.push(row);
    }
  };
  const abdominal = isAbdominoPelvic(scope) || (isCt(scope) && isAbdominoPelvic(complaint));
  const thorax = isThoracic(scope);
  if (abdominal) {
    if (fid.test(complaint) || /appendicite|appendice|douleur iliaque droite/.test(complaint))
      add('douleur de fosse iliaque droite', appendix);
    if (lig.test(complaint) || /diverticulite sigmo/.test(complaint))
      add('douleur de fosse iliaque gauche', lowerLeft);
    if (ruq.test(complaint) || /cholecyst|colique hepat/.test(complaint))
      add('douleur de l’hypochondre droit', rightUpper);
    if (flank.test(complaint) || /hematur|pyeloneph|calcul ureter|lithiase ureter/.test(complaint))
      add('colique néphrétique / douleur lombaire', renal);
    if (pelvic.test(complaint) || /douleur ovar|torsion ovar|annex|gynecolog/.test(complaint)) {
      add('douleur pelvienne', [
        appendix[0], appendix[1], appendix[4], appendix[8],
      ]);
    }
    if (/(douleur abdominale|abdomen aigu|syndrome occlus|vomissement|arret des matieres|peritonite|distension abdominale)/.test(complaint))
      add('douleur abdominale et urgence digestive', acuteAbd);
    if (/icter|cholestase|bilirubine|jaunisse/.test(complaint))
      add('ictère / syndrome cholestatique', rightUpper.slice(1));
    if ((entries.length > 0 || /douleur|pelvi|enceint/.test(complaint)) && sex === 'female'
        && (fid.test(complaint) || lig.test(complaint) || pelvic.test(complaint) ||
          /douleur ovar|annex|gynecolog|grossess/.test(complaint)))
      add('diagnostics gynécologiques', femalePelvis);
  }
  if (thorax && /(dyspn|essouffl|difficulte respir|chest pain|douleur thorac|douleur pleurale|hypox|toux|fievre)/.test(complaint))
    add('sémiologie thoracique', dyspnea);
  if (thorax && /(embolie|douleur thorac|dyspn|hypox)/.test(complaint)
      && /(angio|arteres pulmon|embol|pulmonary angiograph)/.test(scope))
    add('angioscanner pulmonaire', vascularThorax);
  if (isBrain(scope) && /(cephal|headache|deficit neurolog|hemipares|avc|confusion|convulsion|trouble vigilance)/.test(complaint))
    add('sémiologie neuroradiologique', brain);
  return { matched: topics.length > 0, entries: entries.slice(0, 22), topics };
}

/** Nontrivial symptoms not found in curated patterns need a SINGLE targeted
 * Groq request rather than silently reverting to an anatomy-only checklist. */
export function needsSymptomExpansion(indication: string, clinical = '') {
  const value = normalizedClinical(indication + ' ' + clinical);
  return /douleur|fievre|fever|vertige|dizziness|hemat[o-u]|hemoptys|saignement|hemorrag|hematur|essouffl|dyspn|toux|vomiss|diarrh|amaigr|icter|paralys|paresth|deficit|engourdissement|syndrome|oedem|edeme|tumefaction|masse|convulsion|malaise|anemie|thrombopen|syndrome infectieux|dysphag|dysurie|retention|incontinence|trouble|seizure|douleur|hypox|ict[eè]re|fracture|traumatisme|suspicion/.test(value);
}
