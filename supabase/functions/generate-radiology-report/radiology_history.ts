import type { SemiologyEntry } from './radiology_semiology.ts';

// Curated risk-based signs: these are physician-checklist prompts, NOT an AI
// interpretation of the patient's images and never an automatic diagnosis.
// Educational references: ACR Imaging of Mesenteric Ischemia, acute abdomen
// imaging, and renal/splenic perfusion defect radiological semiology.

export type HistorySemio = {
  matched: boolean; flagged: boolean; entries: SemiologyEntry[];
  topics: string[];
};
const normalize = (value: string) => value.normalize('NFD')
  .replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[’']/g,' ');

const embolic: SemiologyEntry[] = [
  ['Antécédents · Vaisseaux mésentériques',
    'Défaut de remplissage ou arrêt de la lumière de l’artère mésentérique supérieure ou de ses branches ?',
    'Pas de défaut de remplissage des artères mésentériques sur les segments correctement opacifiés par une phase artérielle adaptée.',
    'Chez un patient avec fibrillation atriale, un embole artériel peut provoquer une ischémie mésentérique aiguë. Une phase veineuse seule ne permet pas de l’exclure.',
    'Suivre tronc et branches de l’AMS, défaut endoluminal, arrêt brutal, embolies distales. Contrôler la PHASE artérielle et l’opacification ; si absente/insuffisante : Non évaluable et discuter angio-TDM.',
    'CT angiography SMA embolus mesenteric arterial occlusion'],
  ['Antécédents · Perfusion intestinale',
    'Défaut ou diminution segmentaire du rehaussement des parois intestinales ?',
    'Pas de défaut de rehaussement des parois intestinales sur les segments opacifiés et phases techniquement évaluables.',
    'Une hypo- ou absence de rehaussement digestif est un signe important de souffrance ischémique. Une ischémie précoce peut exister sans signes pariétaux.',
    'Comparer rehaussement des anses adjacentes ; territoire vasculaire, segment, amincissement/épaississement, distribution. Sans contraste IV ou sans phase adaptée : Non évaluable.',
    'contrast CT acute bowel ischemia diminished bowel wall enhancement'],
  ['Antécédents · Souffrance intestinale',
    'Pneumatose intestinale, aéroportie, distension ou épanchement associé à une souffrance digestive ?',
    'Pas de pneumatoses ni de gaz portal détectables ; ceci n’exclut pas une ischémie intestinale.',
    'Pneumatose, gaz veineux portal et épanchement peuvent accompagner une ischémie évoluée mais ne sont ni nécessaires ni toujours spécifiques.',
    'Identifier gaz intramural, ramification du gaz portal périphérique, paroi, anse dilatée, liquide et retentissement mésentérique ; corréler aux vaisseaux.',
    'CT bowel ischemia pneumatosis portal venous gas'],
  ['Antécédents · Rate',
    'Plage splénique périphérique triangulaire ou segmentaire sans rehaussement évoquant un infarctus ?',
    'Pas de défaut de perfusion splénique focal évident sur une phase portale d’interprétation suffisante.',
    'L’infarctus splénique embolique peut produire un défaut de perfusion cunéiforme périphérique. Les différences transitoires de perfusion selon la phase sont un piège.',
    'Chercher hypodensité triangulaire à base capsulaire, comparer les phases, évaluer artère splénique et présence de complications ; sans injection : Non évaluable.',
    'contrast CT splenic infarction wedge shaped hypodensity'],
  ['Antécédents · Reins',
    'Défaut de perfusion rénale triangulaire cortical ou non-rehaussement segmentaire ?',
    'Pas de défaut de perfusion rénale focal identifié sur les phases permettant l’évaluation du néphrogramme.',
    'Un infarctus rénal embolique peut présenter une plage triangulaire de non-rehaussement ; différencier de pyélonéphrite ou anomalie du temps de contraste.',
    'Rechercher coin hyporehaussé vers la capsule, limite nette, signe du cortical rim si présent ; suivre artère rénale si phase artérielle, comparer aux signes inflammatoires et au protocole.',
    'CT renal infarction wedge shaped cortical perfusion defect'],
  ['Antécédents · Artères rénales et spléniques',
    'Thrombus ou interruption de l’opacification des artères rénales ou spléniques visibles ?',
    'Pas de défaut de remplissage identifié sur les segments artériels techniquement opacifiés et évaluables.',
    'L’embolie systémique peut toucher plusieurs artères viscérales simultanément : une embolie rénale ou splénique peut accompagner une ischémie mésentérique.',
    'Rechercher thrombus intraluminal, arrêt brutal, territoire distal non perfusé et multiples infarctus. Ne jamais déclarer ces artères perméables si la phase est non artérielle.',
    'CTA renal splenic artery embolus occlusion'],
];
const postoperative: SemiologyEntry[] = [
  ['Antécédents · Chirurgie digestive', 'Hernie interne, bride ou transition occlusive sur un trajet postopératoire ?',
    'Pas de syndrome occlusif mécanique avec zone de transition visible sur les segments évalués.',
    'Après chirurgie, brides et hernies internes peuvent entraîner une occlusion ; chercher signes de strangulation.',
    'Dilatation, transition, closed loop, tourbillon mésentérique, rehaussement, graisse et collection selon protocole.',
    'CT postoperative internal hernia closed loop bowel obstruction'],
  ['Antécédents · Site opératoire', 'Collection ou complication inflammatoire de la loge opératoire visible ?',
    'Pas de collection de la loge opératoire individualisée dans le champ évalué.',
    'Les complications postopératoires dépendent du délai et du geste ; ne pas supposer une anastomose si le geste est inconnu.',
    'Interroger date, type d’intervention et localisation ; rechercher collection, extravasation visible selon protocole, air anormal et infiltration.',
    'CT postoperative abdominal abscess surgical site'],
];
const hemorrhage: SemiologyEntry[] = [
  ['Antécédents · Saignement', 'Hématome intra-abdominal, rétropéritonéal ou pariétal visible ?',
    'Pas d’hématome évident dans les espaces abdomino-pelviens évalués.',
    'Sous anticoagulant, un saignement spontané peut survenir dans le psoas, la paroi ou les espaces rétropéritonéaux.',
    'Densité spontanée, niveau hématocrite, taille, topographie, retentissement ; vérifier phase sans injection si disponible.',
    'CT retroperitoneal psoas hematoma anticoagulation'],
  ['Antécédents · Extravasation', 'Fuite active de contraste dans une collection sanguine sur les phases adaptées ?',
    'Pas d’extravasation active identifiée sur les phases vasculaires acquises et interprétables.',
    'Une extravasation de contraste est une complication d’hémorragie évolutive, mais son absence sur une phase inadéquate n’exclut pas le saignement.',
    'Comparer phase artérielle et tardive si disponibles ; foyer hyperdense évolutif au sein de l’hématome, artère source et volume.',
    'CT arterial contrast extravasation active abdominal hemorrhage'],
];
const cancer: SemiologyEntry[] = [
  ['Antécédents · Oncologie', 'Lésions secondaires viscérales, ganglionnaires ou péritonéales visibles ?',
    'Pas de lésion viscérale, ganglionnaire ou péritonéale suspecte identifiée sur les segments évalués.',
    'Chez un patient ayant un cancer connu, rechercher atteinte secondaire dans le champ, sans requalifier toute lésion indéterminée comme métastase.',
    'Décrire nombre, taille, densité, rehaussement et topographie selon phases ; comparer aux examens antérieurs.',
    'CT abdominal metastases liver peritoneal carcinomatosis'],
  ['Antécédents · Thrombose', 'Thrombose veineuse abdomino-pelvienne visible sur la phase adaptée ?',
    'Pas de thrombus veineux identifié sur les troncs opacifiés évaluables.',
    'Les néoplasies augmentent le risque thromboembolique, mais l’absence d’une phase adaptée empêche l’exclusion.',
    'Évaluer axes ilio-caves et mésentériques opacifiés, défaut de remplissage, collatéralité ; spécifier limites de phase.',
    'contrast CT portal mesenteric vein thrombosis'],
];
const immunosuppress: SemiologyEntry[] = [
  ['Antécédents · Infection', 'Collection, abcès ou foyer infectieux atypique chez ce patient immunodéprimé ?',
    'Pas de collection organisée visible dans le champ et sur les phases étudiés.',
    'L’immunodépression élargit les causes infectieuses, y compris les présentations moins inflammatoires ; ne pas interpréter une graisse peu infiltrée comme absence d’infection.',
    'Chercher collection à paroi rehaussée, hypoatténuation d’organe, atteinte digestive et ganglions ; relier aux signes cliniques.',
    'CT immunosuppressed intraabdominal abscess infection'],
];
export function historyRiskSemiology(args: {
 exam: string; region: string; indication: string; clinical?: string; technique?: string;
}): HistorySemio {
  const history = normalize(args.indication + ' ' + (args.clinical || ''));
  const scope = normalize(args.exam + ' ' + args.region + ' ' + (args.technique || ''));
  const ct = /\b(tdm|ct|scanner|tomodensitometrie|angio.tdm)\b/.test(scope);
  const abdominal = /abdom|pelv|bassin|\btap\b|thoraco.abdom|renal|rein|uro/.test(scope);
  const entries: SemiologyEntry[] = [], topics: string[] = [];
  const add = (topic: string, rows: SemiologyEntry[]) => {
    topics.push(topic);
    for (const row of rows) if (!entries.some(e=>e[1]===row[1])) entries.push(row);
  };
  if (ct && abdominal) {
    if (/\bacfa\b|fibrillation (auriculaire|atriale)|fibrillation des oreillettes|\bfa (chronique|connue|paroxystique|permanente)\b|arythmie complete par fibrillation/.test(history))
      add('fibrillation atriale / embolies viscérales', embolic);
    if (/antecedent.{0,30}(chirurg|operat)|\bpost.?operat|cholecystectomie|colectomie|appendicectomie|bypass gastrique|anastomos/.test(history))
      add('antécédent chirurgical', postoperative);
    if (/anticoagul|apixaban|rivaroxaban|dabigatran|warfarin|coumadine|avk|heparine|enoxaparine/.test(history))
      add('traitement anticoagulant / risque hémorragique', hemorrhage);
    if (/cancer|carcinome|neoplas|metastas|lymphome|oncologi/.test(history))
      add('antécédent oncologique', cancer);
    if (/immunodepr|immunosupp|corticotherapie|greffe|transplant|chimiotherapie/.test(history))
      add('immunodépression', immunosuppress);
  }
  const flagged = /\b(acfa|atcd|hta|diabete|tabag|cardiopath|valvulopath|avc|fibrillation|thrombophil|thromboembol|embol|anticoagul|chimiotherap|immunodepr|greffe|chirurg|operat|antecedent|vascular|atheroscler|anemie|lithiase|crohn|cancer|cirrhos|hepatite|inflammatoire|insuffisance|prothese|infectio|traumatisme)\b/.test(history);
  return {matched: topics.length>0,flagged,entries:entries.slice(0,13),topics};
}
