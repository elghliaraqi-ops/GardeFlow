import { indicationSemiology, type AnatomicSex } from './radiology_semiology.ts';

// High-yield anatomical checklists, NOT patient results. No stored images or patient data.
// Keep the systematic order even when a rare lesion is mentioned in the indication.
export type GuidedQuestion = {
  id: string; kind: 'qcu' | 'qcm' | 'texte'; section: string; title: string;
  definition: string; criteria: string[]; options: string[];
  reference_query: string; normal_text: string; abnormal_text: string;
};
type Entry = [string, string, string, string, string, string?];
function q(rows: Entry[], modality: string): GuidedQuestion[] {
  return rows.map((r, i) => ({
    id: 'q' + (i + 1), kind: 'qcu', section: r[0], title: r[1],
    definition: r[3],
    criteria: [r[4], 'Préciser siège, côté, étendue et mesures seulement s’ils sont constatés.'],
    options: [], reference_query: modality + ' ' + (r[5] || r[1]),
    normal_text: r[2], abnormal_text: r[1].replace(/[?？]$/, '') + '.',
  }));
}
function s(s: string): string {
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
}
const sinus: Entry[] = [
  ['Sinus', 'Épaississement muqueux ou comblement maxillaire ?', 'Sinus maxillaires correctement aérés, sans épaississement muqueux.', 'Analyse de la muqueuse et du contenu des sinus maxillaires.', 'Rechercher opacités muqueuses pariétales, comblement partiel/total, latéralité.', 'maxillary sinus mucosal thickening axial coronal'],
  ['Sinus', 'Épaississement muqueux ou comblement frontal ?', 'Sinus frontaux correctement aérés, sans épaississement muqueux.', 'Analyse du contenu et de la muqueuse des sinus frontaux.', 'Examiner les sinus frontaux droit et gauche et préciser extension.', 'frontal sinus opacification CT'],
  ['Sinus', 'Comblement ou épaississement des cellules ethmoïdales ?', 'Cellules ethmoïdales correctement aérées.', 'Analyse des cellules ethmoïdales antérieures et postérieures.', 'Évaluer cellules antérieures/postérieures et le côté.', 'ethmoid mucosal thickening CT'],
  ['Sinus', 'Épaississement muqueux ou comblement sphénoïdal ?', 'Sinus sphénoïdal correctement aéré, sans épaississement muqueux.', 'Analyse du sinus sphénoïdal.', 'Chercher épaississement muqueux, sécrétions, comblement et latéralité.', 'sphenoid sinus opacification CT'],
  ['Sinus', 'Niveau hydro-aérique ou contenu hyperdense dans les sinus ?', 'Absence de niveau hydro-aérique ou de contenu spontanément hyperdense dans les sinus examinés.', 'Recherche de liquide ou de contenu dense.', 'Niveaux horizontaux, bulles, hyperdensités spontanées ; ne pas déduire une infection de la seule imagerie.', 'air fluid level paranasal sinus CT'],
  ['Voies de drainage', 'Obstruction des complexes ostioméataux ?', 'Complexes ostioméataux libres bilatéralement.', 'Voies de drainage maxillaires et ethmoïdales antérieures.', 'Vérifier infundibulums et complexes ostioméataux droit et gauche.', 'ostiomeatal unit obstruction CT'],
  ['Voies de drainage', 'Obstruction des récessus frontaux ou sphéno-ethmoïdaux ?', 'Voies de drainage frontales et récessus sphéno-ethmoïdaux perméables.', 'Examen des voies de drainage des sinus frontaux et sphénoïdaux.', 'Évaluer perméabilité, comblement et latéralité.', 'frontal recess sphenoethmoidal recess CT'],
  ['Fosses nasales', 'Déviation significative ou éperon de la cloison nasale ?', 'Cloison nasale sans déviation significative ni éperon obstructif.', 'Analyse septale.', 'Préciser sens, siège, éperon et retentissement sur la fosse nasale.', 'nasal septum deviation CT'],
  ['Fosses nasales', 'Concha bullosa ou variante des cornets moyens ?', 'Absence de concha bullosa ou d’anomalie significative des cornets moyens.', 'Pneumatisation des cornets et variantes.', 'Rechercher concha bullosa, cornet paradoxal et leur effet sur le méat moyen.', 'concha bullosa coronal CT'],
  ['Fosses nasales', 'Masse, polypose ou hypertrophie obstructive des fosses nasales ?', 'Pas de lésion tissulaire obstructive identifiable dans les fosses nasales.', 'Analyse des fosses nasales et du cavum visible.', 'Rechercher formations polypoïdes, asymétrie et obstruction.', 'nasal polyp CT sinus'],
  ['Structures dentaires', 'Matériel dentaire ectopique ou origine odontogène suspecte ?', 'Pas de matériel dentaire ectopique dans les sinus maxillaires visibles.', 'Rapports du plancher maxillaire avec les dents et racines.', 'Rechercher corps étrangers, communication bucco-sinusienne et foyer périapical visible.', 'odontogenic sinusitis CT dental foreign body'],
  ['Parois osseuses', 'Lésion osseuse agressive, lyse ou ostéocondensation suspecte ?', 'Pas de lésion osseuse focale agressive visible des parois sinusiennes.', 'Analyse des parois en fenêtre osseuse.', 'Vérifier remodelage, lyse, condensation et réaction osseuse ; ne pas confondre hyperostose chronique et tumeur.', 'sinus bone destruction CT'],
  ['Variantes à risque chirurgical', 'Déhiscence de la lame criblée ou asymétrie à risque du toit ethmoïdal ?', 'Pas de déhiscence évidente du toit ethmoïdal et de la lame criblée.', 'Examen de la base du crâne antérieure.', 'Keros/hauteur des fosses olfactives si pertinente, asymétrie et déhiscence réelle ; le type de Keros ne se présume pas.', 'CT sinus cribriform plate Keros classification'],
  ['Variantes à risque chirurgical', 'Déhiscence ou anomalie de la lame papyracée ?', 'Lames papyracées sans déhiscence osseuse identifiée.', 'Paroi orbitaire médiale.', 'Chercher déhiscence, hernie graisseuse et séquelle de fracture.', 'lamina papyracea dehiscence CT'],
  ['Variantes à risque chirurgical', 'Cellule d’Onodi ou rapport particulier avec le nerf optique ?', 'Pas de cellule d’Onodi à rapport optique à risque identifiée.', 'Rapports ethmoïde postérieur, sphénoïde et nerf optique.', 'Identifier cellule sphéno-ethmoïdale latéralisée, procidence et déhiscence du canal optique.', 'Onodi cell CT sinus optic nerve'],
  ['Variantes à risque chirurgical', 'Procidence ou déhiscence des canaux carotidiens ou optiques ?', 'Pas de déhiscence osseuse visible des canaux carotidiens ou optiques.', 'Rapports des canaux vasculonerveux avec le sphénoïde.', 'Analyser canaux carotidiens internes et optiques, surtout en fenêtre osseuse.', 'optic carotid canal dehiscence sphenoid CT'],
  ['Variantes à risque chirurgical', 'Trajet à risque de l’artère ethmoïdale antérieure ?', 'Pas de trajet bas ou déhiscence clairement identifié de l’artère ethmoïdale antérieure.', 'Trajet de l’artère ethmoïdale antérieure.', 'Repérer canal de l’artère ethmoïdale antérieure, déhiscence et trajet infra-ethmoïdal ; ne pas affirmer en cas de résolution insuffisante.', 'anterior ethmoidal artery canal dehiscence CT'],
];
const brainCt: Entry[] = [
  ['Parenchyme cérébral','Hémorragie intracrânienne ?', 'Pas de foyer hémorragique intracrânien visible.', 'Recherche de saignement intra- ou extra-axial.', 'Fenêtres cérébrale et osseuse, densité et distribution.'],
  ['Parenchyme cérébral','Hypodensité focale ou perte de différenciation substance grise-blanche ?', 'Différenciation substance grise-blanche conservée, sans hypodensité focale évidente.', 'Recherche de signe d’ischémie ou d’œdème.', 'Insula, noyaux gris et territoires vasculaires.'],
  ['Parenchyme cérébral','Lésion expansive, œdème ou effet de masse ?', 'Pas d’effet de masse ni d’œdème vasogénique évident.', 'Recherche de processus expansif.', 'Localisation, dimensions et déplacement des structures.'],
  ['Système ventriculaire','Hydrocéphalie ou dilatation ventriculaire pathologique ?', 'Système ventriculaire sans dilatation pathologique.', 'Analyse de la taille ventriculaire.', 'Ventricules latéraux, III et IV, signes transépendymaires.'],
  ['Système ventriculaire','Déviation de la ligne médiane ou engagement ?', 'Structures médianes en place, sans signe d’engagement.', 'Analyse des lignes médianes.', 'Septum pellucidum, faux du cerveau, citernes.'],
  ['Espaces extra-axiaux','Collection extra-axiale ou anomalie des espaces sous-arachnoïdiens ?', 'Pas de collection extra-axiale visualisée.', 'Recherche sous-dural, extradural, sous-arachnoïdien.', 'Contours et densités des espaces.'],
  ['Fosse postérieure','Anomalie cérébelleuse ou du tronc visible ?', 'Pas d’anomalie évidente des structures de la fosse postérieure.', 'Analyse de la fosse postérieure.', 'Prendre en compte les artéfacts osseux éventuels.'],
  ['Structures osseuses','Fracture ou lésion osseuse suspecte ?', 'Pas de lésion osseuse agressive identifiée sur les structures examinées.', 'Analyse de la voûte et de la base.', 'Fenêtre osseuse, contexte traumatique.'],
];
const chestCt: Entry[] = [
  ['Parenchyme pulmonaire','Consolidation alvéolaire ou foyer infectieux ?', 'Pas de foyer de condensation alvéolaire systématisé.', 'Analyse de la densité parenchymateuse.', 'Rechercher bronchogramme aérique et distribution lobaire.'],
  ['Parenchyme pulmonaire','Verre dépoli ou anomalies interstitielles ?', 'Pas d’opacité en verre dépoli ou d’anomalie interstitielle évidente.', 'Anomalies de l’atténuation et de l’interstitium.', 'Répartition, septas, rayon de miel si présents.'],
  ['Parenchyme pulmonaire','Nodule ou masse pulmonaire ?', 'Pas de nodule ou masse pulmonaire suspecte identifié.', 'Recherche lésion nodulaire.', 'Taille, densité, nombre, siège et contours.'],
  ['Voies aériennes','Dilatations bronchiques ou impactions muqueuses ?', 'Pas de dilatations bronchiques ni d’impaction muqueuse notable.', 'Calibre et contenu bronchique.', 'Comparer bronche/artère, arbre en bourgeons.'],
  ['Plèvres','Épanchement pleural ou pneumothorax ?', 'Pas d’épanchement pleural ni de pneumothorax.', 'Examen des cavités pleurales.', 'Déclivité, cloisonnement, air extra-pulmonaire.'],
  ['Médiastin','Adénopathies médiastinales ou hilaires ?', 'Pas d’adénomégalie médiastino-hilaire significative.', 'Étude ganglionnaire.', 'Petit axe des ganglions et territoires.'],
  ['Cœur et vaisseaux','Anomalie cardiovasculaire morphologique visible ?', 'Pas d’anomalie morphologique cardio-vasculaire évidente sur les segments évaluables.', 'Cœur, aorte et artères pulmonaires suivant protocole.', 'Ne pas exclure EP sans protocole adapté.'],
  ['Paroi et os','Lésion osseuse thoracique suspecte ?', 'Pas de lésion osseuse thoracique agressive visible.', 'Structures osseuses et paroi.', 'Fenêtre osseuse, parties molles.'],
];
const abdomenCt: Entry[] = [
  ['Foie et voies biliaires','Lésion focale hépatique ou anomalie du parenchyme ?', 'Foie sans lésion focale suspecte identifiée sur les phases réalisées.', 'Analyse morphologique et focalisation hépatique.', 'Densité, contours, taille, rehaussement si injecté.'],
  ['Foie et voies biliaires','Dilatation des voies biliaires ?', 'Voies biliaires intra- et extrahépatiques non dilatées.', 'Calibre des voies biliaires.', 'Cohérence avec l’âge, cholécystectomie et phases.'],
  ['Vésicule biliaire','Épaississement pariétal ou anomalie vésiculaire ?', 'Pas d’anomalie morphologique vésiculaire évidente.', 'Vésicule et environnement.', 'Paroi, calculs visibles, graisse adjacente.'],
  ['Pancréas et rate','Anomalie pancréatique focale ou inflammatoire ?', 'Pas d’anomalie morphologique pancréatique évidente.', 'Pancréas, canal, environnement.', 'Rehaussement, infiltration, collections.'],
  ['Pancréas et rate','Anomalie splénique focale ?', 'Rate sans lésion focale suspecte visible.', 'Analyse splénique.', 'Taille, densité et rehaussement.'],
  ['Reins et surrénales','Lésion rénale, calcul ou obstacle urinaire ?', 'Pas d’anomalie morphologique rénale ou de dilatation des cavités.', 'Analyse des reins et voies excrétrices.', 'Rehaussement si protocole adapté ; calculs si phase sans injection.'],
  ['Reins et surrénales','Masse surrénalienne ?', 'Surrénales sans nodule suspect identifié.', 'Analyse des glandes surrénales.', 'Dimensions et densité spontanée si disponible.'],
  ['Tube digestif','Épaississement digestif ou syndrome occlusif ?', 'Pas de dilatation digestive ni d’épaississement pariétal évident.', 'Analyse de l’intestin.', 'Calibre, transition, paroi, graisse.'],
  ['Péritoine','Épanchement, pneumopéritoine ou collection ?', 'Pas d’épanchement, de pneumopéritoine ni de collection intra-abdominale.', 'Cavité péritonéale.', 'Liquide libre, bulles, rehaussement périphérique.'],
  ['Vaisseaux et ganglions','Anomalie vasculaire ou adénopathie ?', 'Pas d’adénomégalie abdomino-pelvienne significative.', 'Vaisseaux et chaînes ganglionnaires.', 'Territoire, petit axe, injection suivant protocole.'],
  ['Pelvis','Anomalie des organes pelviens visibles ?', 'Pas d’anomalie pelvienne morphologique évidente sur les organes évaluables.', 'Vessie et organes pelviens.', 'Distension vésicale, morphologie et limites.'],
  ['Os et parois','Lésion osseuse agressive ou anomalie pariétale ?', 'Pas de lésion osseuse agressive visible.', 'Parois et squelette.', 'Fenêtre osseuse et hernies.'],
];
// Only exam-covered pelvic structures; no presumed gender or contrast phase.
const tapPelvis: Entry[] = [
  ['Vessie', 'Anomalie de la paroi ou du contenu vésical ?', 'Pas d’anomalie morphologique vésicale évidente sur les segments et le degré de remplissage évaluables.', 'Analyse du contenu et des parois de la vessie.', 'Apprécier réplétion, épaississement, calcul ou formation focale visible ; une vessie peu remplie peut être non évaluable.', 'bladder wall thickening pelvic CT'],
  ['Organes pelviens', 'Anomalie des organes génitaux pelviens évaluables ?', 'Pas d’anomalie morphologique évidente des organes génitaux pelviens évaluables.', 'Utérus et annexes ou prostate et vésicules séminales selon l’anatomie présente.', 'Vérifier taille, contours, masses et limites de la TDM ; ne pas présumer une structure non identifiable.', 'uterus adnexa prostate seminal vesicles CT anatomy'],
  ['Tube digestif pelvien', 'Anomalie du rectum, du sigmoïde ou des anses pelviennes ?', 'Pas d’épaississement rectosigmoïdien ni de dilatation des anses pelviennes visibles.', 'Exploration du tube digestif pelvien.', 'Rechercher épaississement, transition, masse, infiltration et collections péridigestives.', 'rectosigmoid bowel wall thickening CT pelvis'],
  ['Péritoine pelvien', 'Épanchement ou collection dans les espaces pelviens ?', 'Pas d’épanchement ni de collection visible dans les espaces pelviens.', 'Analyse des récessus pelviens et de la graisse adjacente.', 'Cul-de-sac rectovésical ou de Douglas selon l’anatomie ; localisation et densité si positif.', 'pelvic free fluid Douglas pouch CT'],
  ['Chaînes ganglionnaires', 'Adénopathies pelviennes ou inguinales suspectes ?', 'Pas d’adénomégalie pelvienne ou inguinale significative sur les territoires visualisés.', 'Analyse des chaînes iliaques, obturatrices et inguinales visibles.', 'Mesurer petit axe et préciser territoire ; distinguer taille et morphologie suspecte.', 'pelvic iliac lymph nodes CT'],
  ['Vaisseaux pelviens', 'Anomalie des axes vasculaires iliaques visible ?', 'Pas d’anomalie morphologique évidente des axes iliaques sur les segments évaluables.', 'Artères et veines iliaques selon phase d’acquisition.', 'Vérifier calibre, perméabilité uniquement si phase adaptée et anomalies périvasculaires.', 'iliac artery vein pelvic CT anatomy'],
  ['Squelette pelvien', 'Lésion osseuse suspecte du bassin ou des hanches ?', 'Pas de lésion osseuse agressive visible des os du bassin et des hanches examinées.', 'Analyse des os iliaques, sacrum, pubis et hanches sur fenêtre osseuse.', 'Rechercher ostéolyse, condensation, tassement ou fracture uniquement selon indication.', 'pelvic bone metastasis osteolytic CT'],
];
function tagged(rows: Entry[], region: string): Entry[] {
  return rows.map(([section, title, normal, definition, criteria, query]) =>
    [region + ' · ' + section, title, normal, definition, criteria, query]);
}
/** Identifies a true TDM thoraco-abdomino-pelvienne, never chest CT alone. */
export function isTapCt(exam: string, region: string, technique = ''): boolean {
  const value = s(exam + ' ' + region + ' ' + technique);
  const ct = /\b(tdm|ct|scanner|tomodensitometrie)\b/.test(value);
  const shorthand = /(?:^|[^a-z])t\s*\.?\s*a\s*\.?\s*p(?:[^a-z]|$)/.test(value);
  const complete = /(thorac|thorax|poumon)/.test(value) &&
    /abdom/.test(value) && /pelv|bassin/.test(value);
  return ct && (shorthand || complete);
}
const temporalCt: Entry[] = [
  ['Oreille externe','Comblement du conduit auditif externe ?', 'Conduits auditifs externes libres.', 'Analyse du conduit externe.', 'Distinguer cérumen, épaississement et érosion.'],
  ['Oreille moyenne','Comblement de la caisse du tympan ?', 'Caisses du tympan aérées.', 'Compartiments mésotympan et épitympan.', 'Préciser compartiments et latéralité.'],
  ['Mastoïde','Comblement mastoïdien ?', 'Cellules mastoïdiennes bien aérées.', 'Aération mastoïdienne.', 'Préciser extension et sclérose associée.'],
  ['Chaîne ossiculaire','Érosion ou discontinuité ossiculaire ?', 'Chaînes ossiculaires respectées.', 'Marteau, enclume et étrier.', 'Continuité et érosion à haute résolution.'],
  ['Attique et scutum','Érosion du scutum ou de l’attique ?', 'Scutum et parois atticales intacts.', 'Recherche de cholestéatome indirect.', 'Érosion osseuse, comblement épitympanique.'],
  ['Labyrinthe','Anomalie du labyrinthe osseux ?', 'Labyrinthes osseux de morphologie conservée.', 'Cochlée, vestibule, canaux semi-circulaires.', 'Déhiscentes, malformations, fistules.'],
  ['Canal facial','Déhiscence du canal du nerf facial ?', 'Pas de déhiscence osseuse évidente du canal facial.', 'Trajet du nerf facial.', 'Préciser segment, résolution suffisante.'],
  ['Os temporal','Lyse ou fracture du rocher ?', 'Pas de fracture ni d’ostéolyse suspecte du rocher.', 'Structures osseuses temporales.', 'Fenêtre osseuse bilatérale.'],
];
const xrayChest: Entry[] = [
  ['Parenchyme pulmonaire','Foyer alvéolaire ou opacité focale ?', 'Pas de foyer de condensation parenchymateuse individualisable.', 'Recherche de lésion alvéolaire.', 'Projection, localisation, bronchogramme.'],
  ['Parenchyme pulmonaire','Surcharge interstitielle ou œdème visible ?', 'Pas de signe radiographique de surcharge interstitielle.', 'Analyse des trames interstitielles.', 'Lignes septales, redistribution, verre dépoli non spécifique sur radio.'],
  ['Plèvres','Épanchement pleural ou pneumothorax ?', 'Culs-de-sac pleuraux libres, sans pneumothorax visible.', 'Analyse des récessus pleuraux.', 'Comblement, ligne pleurale, décubitus.'],
  ['Cardiomédiastin','Cardiomégalie ou élargissement médiastinal ?', 'Silhouette cardio-médiastinale sans élargissement manifeste.', 'Analyse du médiastin.', 'Tenir compte projection AP et rotation.'],
  ['Os et parties molles','Lésion osseuse visible ou dispositif mal positionné ?', 'Pas d’anomalie osseuse aiguë évidente sur le champ exploré.', 'Structures osseuses et dispositifs.', 'Projection, matériel présent, limites techniques.'],
];
const brainMri: Entry[] = [
  ['Parenchyme','Lésion de diffusion restreinte ?', 'Pas de restriction de diffusion focale visible.', 'Séquences DWI/ADC.', 'Concordance hypersignal DWI et baisse ADC.'],
  ['Parenchyme','Anomalie FLAIR/T2 focale ou diffuse ?', 'Pas d’anomalie significative du signal parenchymateux T2/FLAIR.', 'Examen de la substance blanche et grise.', 'Topographie, symétrie, extension.'],
  ['Parenchyme','Lésion hémorragique ou dépôt de susceptibilité ?', 'Pas de foyer hémorragique identifiable sur les séquences sensibles à la susceptibilité.', 'T2*/SWI si acquises.', 'Baisse de signal de susceptibilité.'],
  ['Parenchyme','Processus expansif ou œdème ?', 'Pas de processus expansif intracrânien identifié.', 'Volumes parenchymateux.', 'Effet de masse, localisation, limites.'],
  ['Rehaussement','Prise de contraste anormale ?', 'Pas de prise de contraste pathologique identifiable.', 'Seulement en cas de gadolinium réellement injecté.', 'Parenchymateux, méningé, lésionnel.'],
  ['Ventricules','Hydrocéphalie ou effet de masse ?', 'Système ventriculaire sans dilatation pathologique ; structures médianes en place.', 'Morphologie ventriculaire.', 'Ventricules et citernes.'],
  ['Fosse postérieure','Anomalie du tronc ou cervelet ?', 'Pas d’anomalie morphologique évidente de la fosse postérieure.', 'Tronc et cervelet.', 'Prendre en compte artéfacts.'],
];
const mriSpine: Entry[] = [
  ['Alignement','Trouble de statique ou listhésis ?', 'Alignement vertébral conservé.', 'Analyse sagittale.', 'Lordose/cyphose, translation.'],
  ['Os et plateaux','Anomalie de signal osseux ou tassement ?', 'Hauteurs vertébrales et signal médullaire osseux sans anomalie focale suspecte.', 'Signal T1/T2/STIR.', 'Plateaux, tassements et infiltration.'],
  ['Disques','Déshydratation, hernie ou protrusion discale ?', 'Pas de hernie discale compressive identifiée.', 'Disques intervertébraux.', 'Niveau, topographie et retentissement.'],
  ['Canal rachidien','Sténose canalaire ?', 'Pas de sténose canalaire significative.', 'Canal rachidien.', 'Calibre, compression et niveaux.'],
  ['Foramens','Sténose foraminale ?', 'Pas de sténose foraminale significative.', 'Foramens droits et gauches.', 'Contact/effacement graisse, racines.'],
  ['Moelle et racines','Anomalie du signal médullaire ou compression radiculaire ?', 'Pas d’anomalie médullaire visible sur les segments évalués.', 'Moelle, cône, queue de cheval.', 'Ne pas conclure sur une région hors champ.'],
  ['Parties molles','Collection ou anomalie paravertébrale ?', 'Pas de collection paravertébrale visible.', 'Tissus adjacents.', 'STIR, rehaussement si injecté.'],
];
const renalCt: Entry[] = [
  ['Reins','Calculs rénaux ?', 'Pas de calcul rénal visible.', 'Calculs sur phases sans injection.', 'Densité, diamètre, pôle et latéralité.'],
  ['Reins','Dilatation pyélocalicielle ?', 'Absence de dilatation des cavités pyélocalicielles.', 'Voies excrétrices intrarénales.', 'Calices, bassinet, côté.'],
  ['Reins','Lésion focale du parenchyme rénal ?', 'Pas de lésion focale rénale suspecte sur les phases réalisées.', 'Parenchyme des reins.', 'Taille, densité et rehaussement selon protocole.'],
  ['Uretères','Calcul urétéral ou obstacle ?', 'Pas de calcul urétéral ni d’urétérohydronéphrose identifié.', 'Trajets urétéraux bilatéraux.', 'Site, taille, retentissement.'],
  ['Uretères','Anomalie urétérale pariétale ou lacune excrétrice ?', 'Pas de lacune ni d’anomalie pariétale urétérale sur les segments opacifiés.', 'Phase excrétrice si réalisée.', 'Non opacifié = non évaluable.'],
  ['Vessie','Masse ou calcul vésical ?', 'Pas de calcul ni de lésion endoluminale vésicale évidente.', 'Lumière et parois vésicales.', 'Distension, rehaussement si disponible.'],
  ['Autres','Infiltration graisseuse ou collection périrénale ?', 'Pas d’infiltration de la graisse périrénale ni de collection.', 'Espaces périrénaux.', 'Collections, densité et taille.'],
];
const ultraAbd: Entry[] = [
  ['Foie','Anomalie échographique hépatique ?', 'Foie d’échostructure homogène sans lésion focale visualisée.', 'Échostructure et contours.', 'Focalisation, échogénicité et dimensions.'],
  ['Voies biliaires','Dilatation des voies biliaires ?', 'Pas de dilatation des voies biliaires visibles.', 'Voies biliaires et cholédoque.', 'Mesure du calibre selon contexte.'],
  ['Vésicule','Calcul ou inflammation vésiculaire ?', 'Pas de calcul vésiculaire visible ni d’épaississement pariétal notable.', 'Vésicule en échographie.', 'Échogène avec cône d’ombre, Murphy et paroi.'],
  ['Pancréas','Anomalie du pancréas visible ?', 'Pas d’anomalie pancréatique échographique sur les segments visibles.', 'Pancréas souvent partiellement masqué.', 'Ne pas déclarer normal si mal vu.'],
  ['Rate','Anomalie splénique ?', 'Rate sans anomalie focale visible.', 'Taille et parenchyme splénique.', 'Échogénicité, mensurations.'],
  ['Reins','Calcul, dilatation ou lésion rénale ?', 'Pas de dilatation des cavités rénales ni de lésion focale visible.', 'Reins bilatéraux.', 'Cortico-médullaire, ombre, calices.'],
  ['Péritoine','Épanchement intrapéritonéal ?', 'Pas d’épanchement intrapéritonéal visualisé.', 'Récessus péritonéaux.', 'Morrison, Douglas selon champ exploré.'],
];
const tapCt: Entry[] = [
  ...tagged(chestCt, 'Thorax'),
  ...tagged(abdomenCt.filter(row => row[0] !== 'Pelvis'), 'Abdomen'),
  ...tagged(tapPelvis, 'Pelvis'),
];
const catalogs: Record<string, Entry[]> = {
  'sinus': sinus, 'brain_ct': brainCt, 'chest_ct': chestCt,
  'tap_ct': tapCt,
  'abdomen_ct': abdomenCt, 'temporal_ct': temporalCt,
  'chest_xray': xrayChest, 'brain_mri': brainMri,
  'spine_mri': mriSpine, 'urinary_ct': renalCt,
  'abdominal_ultrasound': ultraAbd,
};
export type ExamTemplate = { key: string; label: string; questions: GuidedQuestion[] };
export function examTemplate(exam: string, region: string, indication = '', technique = '', sex: AnatomicSex = 'unknown', clinical = ''): ExamTemplate | null {
  const e = s(exam), r = s(region), ind = s(indication), tech = s(technique);
  let key = '';
  if (isTapCt(exam, region, technique)) key = 'tap_ct';
  else if (/(sinus|rhin|naso.sinus)/.test(r + ' ' + e) && /(tdm|ct|scanner)/.test(e)) key = 'sinus';
  else if (/(rocher|temporal|oreille)/.test(r) && /(tdm|ct|scanner)/.test(e)) key = 'temporal_ct';
  else if (/(uro|rein|urinaire|renal)/.test(r + ' ' + e) && /(tdm|ct|scanner)/.test(e)) key = 'urinary_ct';
  else if (/(cerveau|encephal|cranien|cerebral|tete)/.test(r) && /(tdm|ct|scanner)/.test(e)) key = 'brain_ct';
  else if (/(thorax|thorac|poumon)/.test(r) && /(radio|xray)/.test(e)) key = 'chest_xray';
  else if (/(thorax|thorac|poumon)/.test(r) && /(tdm|ct|scanner)/.test(e)) key = 'chest_ct';
  else if (/(abdom|pelvi|digestif|hepat)/.test(r) && /(tdm|ct|scanner)/.test(e)) key = 'abdomen_ct';
  else if (/(cerveau|encephal|cranien|cerebral)/.test(r) && /irm/.test(e)) key = 'brain_mri';
  else if (/(rachis|cervical|lombaire|dorsal|medullaire)/.test(r) && /irm/.test(e)) key = 'spine_mri';
  else if (/(abdom|hepat|biliaire)/.test(r) && /(echo|ultra)/.test(e)) key = 'abdominal_ultrasound';
  if (!key) return null;
  const rows = catalogs[key].filter(row => {
    if (key === 'brain_mri' && row[0] === 'Rehaussement')
      return /(inject|gadolinium)/.test(tech) && !/(sans injection|non inject)/.test(tech);
    if (key === 'urinary_ct' && row[3].includes('Phase excrétrice'))
      return /(excret|tardive|urograph)/.test(tech);
    return true;
  });
  const qs = q(rows, exam);
  if (key === 'sinus' && /(traum|fracture|choc)/.test(ind)) {
    qs.push(...q([['Parois osseuses', 'Fracture traumatique des parois sinusiennes ou orbitaires ?',
      'Pas de trait de fracture visible des parois sinusiennes et orbitaires examinées.',
      'Recherche de fracture dans le contexte traumatique.',
      'Fenêtre osseuse, décroché cortical, déplacement, hémosinus, latéralité.',
      'maxillary sinus wall orbital floor fracture CT']], exam));
  }
  if (key === 'sinus' && /(chirurg|fess|pre.oper|preoper)/.test(ind)) {
    qs.push(...q([['Variantes à risque chirurgical',
      'Cellules de Haller et variantes du processus unciné gênant le drainage ?',
      'Pas de variante du processus unciné ou de cellules infra-orbitaires rétrécissant le méat moyen.',
      'Rapports du processus unciné et des cellules infra-orbitaires.',
      'Distinguer variante anatomique sans effet d’une obstruction fonctionnelle.',
      'Haller cell uncinate process CT']], exam));
  }
  // Every recognized symptom introduces pathology-specific discriminating
  // radiological signs; anatomy is still read in full after them.
  const focused = indicationSemiology({
    exam, region, indication, clinical, technique, sex,
  });
  if (focused.entries.length) {
    const focusedQuestions = q(focused.entries, exam);
    // Keep a single systematic checklist, no extra Groq request for known
    // indication syndromes and no assumption about image findings.
    qs.unshift(...focusedQuestions);
  }
  // Generic pelvic organ question is NOT evidence for the actual adnexa:
  // when the anatomy is specified, ask separately about the relevant organs.
  if ((key === 'abdomen_ct' || key === 'tap_ct') && sex === 'female') {
    const gyn: Entry[] = [
      ['Pelvis · Annexes', 'Anomalie morphologique de l’utérus ou des annexes identifiables ?',
        'Pas de lésion utéro-annexielle volumineuse évidente dans le champ évalué, sans exclure une pathologie gynécologique fonctionnelle ou vasculaire.',
        'L’utérus et les annexes doivent être décrits distinctement lorsqu’ils sont présents et évaluables.',
        'Décrire utérus, ovaires, masse/kyste, position, épanchement et limites TDM ; ne pas déclarer les ovaires normaux s’ils ne sont pas identifiés.',
        'CT normal uterus ovaries adnexa pelvic anatomy'],
    ];
    qs.push(...q(gyn, exam));
  }
  if ((key === 'abdomen_ct' || key === 'tap_ct') && sex === 'male') {
    qs.push(...q([['Pelvis · Prostate', 'Anomalie prostatique ou des vésicules séminales identifiables ?',
      'Pas d’anomalie morphologique évidente de la prostate ou des vésicules séminales sur le champ évalué.',
      'Analyse adaptée à une anatomie prostatique lorsqu’elle est présente.',
      'Taille, contours, asymétries, masse ou infiltration visibles, en tenant compte des limites de la TDM.',
      'CT prostate seminal vesicles normal anatomy']], exam));
  }
  qs.forEach((v, i) => v.id = 'q' + (i + 1));
  return { key, label: key === 'tap_ct' ? 'Scanner thoraco-abdomino-pelvien'
    : key === 'sinus' ? 'Scanner des sinus' : region, questions: qs };
}
