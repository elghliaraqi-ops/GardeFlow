/**
 * Conservative French radiology prose helpers.
 * No diagnoses are inferred: the physician's observed status, wording,
 * laterality and measurements are the only data for a reported finding.
 */
export function sentence(input: string): string {
  const cleaned = input.replace(/^[\s•-]+/, '').replace(/\s+/g, ' ')
    .replace(/\s+[?？]\s*$/, '').replace(/\.+\s*$/, '').trim();
  if (!cleaned) return '';
  return cleaned[0].toLocaleUpperCase('fr') + cleaned.slice(1) + '.';
}
const rawTerm = (value: string) =>
  value.replace(/^[\s•-]+/, '').replace(/[\s?？.]+$/, '').trim();
const lowerFirst = (value: string) => value.length
  ? value[0].toLocaleLowerCase('fr') + value.slice(1) : '';
const vague = /\b(?:ou|et\/ou)\b/i;
function explicitSentence(text: string): boolean {
  // A doctor's complete descriptive radiology sentence is never replaced
  // by a generic template, even when the question was QCU/QCM.
  const v = text.trim();
  return /^(?:le |la |les |l['’]|un |une |des |au |aux |on |il existe|il s'agit|mise en évidence|présence |absence |aspect |appendice |foie |rate |rein |pancréas |vessie |utérus |ovaire |artère |plèvre |poumon |parenchyme |épaississement |infiltration |épanchement |formation |collection |nodule |masse |foyer |sinus |chaîne |vésicule |côlon |iléo|anses |mésentère |adénopathie )/i.test(v)
    && (v.length >= 34 || /[.;]/.test(v));
}
/**
 * An isolated positive sign without an exact physician description must
 * remain descriptive and limited; disjunctions aren't asserted as two signs.
 */
export function positiveDescription(
  question: string,
  abnormalText: string,
  notes = '',
): string {
  const n = notes.trim();
  if (n && explicitSentence(n)) return sentence(n);
  const title = rawTerm(abnormalText || question);
  const generic = title.replace(/^(?:y a.t.il|existe.t.il)\s+/i, '');
  const ambiguous = vague.test(generic) || /[?？]/.test(generic);
  let body = '';
  if (ambiguous) {
    // Choice of which alternative is present must be specified by the reader.
    body = 'Anomalie visualisée parmi les signes recherchés (' +
      rawTerm(question).toLocaleLowerCase('fr') + '), à caractériser';
  } else if (/^infiltration\b/i.test(generic)) {
    body = 'On note une ' + lowerFirst(generic);
  } else if (/^(épaississement|epaississement|défaut|foyer|calcul|nodule|thrombus)\b/i.test(generic)) {
    body = 'On observe un ' + lowerFirst(generic);
  } else if (/^(dilatation|collection|lésion|masse|anomalie|opacité|hydronéphrose)\b/i.test(generic)) {
    body = 'On observe une ' + lowerFirst(generic);
  } else if (/^(épanchement|epanchement|pneumothorax|hématome|hematome)\b/i.test(generic)) {
    body = 'On note un ' + lowerFirst(generic);
  } else if (/^appendice dilaté\b/i.test(generic)) {
    body = 'L’appendice apparaît dilaté' + generic.slice('Appendice dilaté'.length);
  } else if (/^(rate|foie|rein|pancréas|vessie|utérus|ovaire|appendice|artère|poumon|sinus)\b/i.test(generic)) {
    body = 'On note : ' + lowerFirst(generic);
  } else {
    body = 'Le signe suivant est observé : ' + lowerFirst(generic);
  }
  // Short notes such as "à droite", "10 mm" still follow the finding.
  return sentence(body + (n ? ' (' + n.replace(/\.+$/, '') + ')' : ''));
}
/** Avoid jargon like "signe : absent" in a degraded provider fallback. */
export function negativeDescription(question: string): string {
  const name = rawTerm(question);
  if (!name) return '';
  if (vague.test(name) || /[?？]/.test(name)) {
    return sentence('Pas de signe en faveur de l’une des anomalies recherchées : ' +
      lowerFirst(name));
  }
  if (/^(présence de|mise en évidence de)\s+/i.test(name)) {
    return sentence('Absence de ' + lowerFirst(name).replace(/^(présence de|mise en évidence de)\s+/i, ''));
  }
  return sentence('Pas de ' + lowerFirst(name) + ' identifié sur les structures évaluées');
}
/** The "Indication/Antécédents" label is a teaching category, not an organ. */
export function reportingSection(section: string, title: string): string {
  if (!/^(?:Indication|Antécédents)\s*[·:]/i.test(section)) return section || 'Constatations';
  const name = (section + ' ' + title).toLocaleLowerCase('fr');
  if (/appendic|iléocæc|cecal|cæcal|iléo/.test(name)) return 'Région iléo-cæcale et appendice';
  if (/splén|rate/.test(name)) return 'Rate';
  if (/rénal|rein|pyélo|urétér|ureter|hydronéphrose/.test(name)) return 'Reins et voies urinaires';
  if (/annex|ovar|utér|salping|tubo/.test(name)) return 'Organes génitaux pelviens';
  if (/mésentéri|artèr|ischémi|perfusion intestin|veine/.test(name)) return 'Vaisseaux abdominaux et perfusion digestive';
  if (/vésicule|biliair|cholédoque/.test(name)) return 'Foie et voies biliaires';
  if (/diverticul|sigmoïd|colit|intestinal|intestin|digestif|occlusion|anse/.test(name)) return 'Tube digestif';
  if (/épanchement|collection|abcès|péritoine|pneumopérit/.test(name)) return 'Péritoine';
  if (/hématom|hémorrag|extravas/.test(name)) return 'Espaces abdomino-pelviens';
  if (/pulmon|alvéol|plèvre|pneumothorax|opacit/.test(name)) return 'Thorax';
  if (/cérébr|intracrân|hémorragie|hydrocéph|ischémi/.test(name)) return 'Encéphale';
  return section.replace(/^(?:Indication|Antécédents)\s*[·:]\s*/i, '');
}
