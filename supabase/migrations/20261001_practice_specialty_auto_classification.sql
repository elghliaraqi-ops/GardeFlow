-- Practice — classement automatique des cas cliniques par spécialité.
-- "Autres cas cliniques" n'est utilisé qu'en dernier recours ; "Urgences"
-- reste réservé aux situations transversales de médecine d'urgence.

create extension if not exists unaccent with schema extensions;

alter table public.clinical_case_posts
  add column if not exists specialty_classification_confidence numeric(4,3),
  add column if not exists specialty_classification_source text,
  add column if not exists specialty_classified_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'clinical_case_posts_specialty_confidence_check'
      and conrelid = 'public.clinical_case_posts'::regclass
  ) then
    alter table public.clinical_case_posts
      add constraint clinical_case_posts_specialty_confidence_check
      check (
        specialty_classification_confidence is null
        or specialty_classification_confidence between 0 and 1
      );
  end if;
end $$;

create or replace function public.clinical_case_classify_specialty(
  p_age_band text,
  p_presentation text,
  p_history text,
  p_clinical_exam text,
  p_complementary_exams text,
  p_imaging_conclusion text,
  p_assessment text,
  p_plan text,
  p_disposition text
)
returns text
language plpgsql
stable
set search_path = public, extensions
as $$
declare
  t text;
begin
  t := lower(extensions.unaccent(concat_ws(' ',
    coalesce(p_presentation,''),
    coalesce(p_history,''),
    coalesce(p_clinical_exam,''),
    coalesce(p_complementary_exams,''),
    coalesce(p_imaging_conclusion,''),
    coalesce(p_assessment,''),
    coalesce(p_plan,''),
    coalesce(p_disposition,'')
  )));
  t := regexp_replace(t, '[^a-z0-9]+', ' ', 'g');

  -- Urologie avant néphrologie pour ne pas perdre les tableaux lithiasiques.
  if t ~ '(colique nephret|calcul (renal|renaux|ureter|urinaire)|lithiase (renal|urinaire|ureter)|uretero?hydro|hydroneph|uretere|hematurie)'
     and t ~ '(lomb|flanc|aine|ureter|lithiase|calcul|colique|hematurie|retention urinaire|prostat|testicul|bourse)' then
    return 'Urologie';
  end if;
  if t ~ '(retention urinaire|hypertrophie benign.*prostat|adenome prostat|cancer prostat|torsion testicul|epididym|orchite|hydrocele|varicocele|tumeur vesic|cancer vesic|stenose uretr|hematurie macroscop)' then
    return 'Urologie';
  end if;

  if t ~ '(fracture|entorse|luxation|traumatisme osteo|orthoped|osteosynth|ligament|menisque|rupture.*tendon|prothese (hanche|genou)|malleol|cheville|gonarthrose|coxarthrose)' then
    return 'Traumatologie / Orthopédie';
  end if;

  if t ~ '(appendicit|cholecystit|angiocholit|peritonit|occlusion intest|hernie.*(etrang|incarc)|perforation digest|diverticulit.*compli|abces intra abdominal|chirurgie viscer|appendicect|colectom|gastrectom)' then
    return 'Chirurgie Viscérale';
  end if;

  if t ~ '(grossesse|enceinte|obstetri|pre eclamps|eclamps|metrorrag|menorrag|amenorrh|fausse couche|grossesse extra uter|geu|travail obstetr|accouchement|gynec|ovar|uter|endometr|col uterin|fibrome)' then
    return 'Gynécologie';
  end if;

  if t ~ '(syndrome coronar|infarct|stemi|nstemi|troponin|angor|insuffisance cardiaque|oedeme aigu poumon|cardiomyopath|fibrillation atrial|flutter|tachycard|bradycard|bloc auriculo|pericardit|endocardit|valvulopath|cardiolog)' then
    return 'Cardiologie';
  end if;

  if t ~ '(hematome (extra dural|sous dural)|compression medull|queue de cheval|hernie discale.*deficit|tumeur cerebr.*chir|hydrocephal|neurochir)' then
    return 'Neurochirurgie';
  end if;
  if t ~ '(avc|accident vasculaire cerebral|hemipar|hemipleg|aphasie|dysarthr|thrombolys|thrombectom|epilep|crise convuls|meningite.*neurolog|sclerose en plaques|parkinson|myasthen|neuropath|neurolog)' then
    return 'Neurologie';
  end if;

  if t ~ '(asthme|bpco|pneumopath|pneumonie|embolie pulmonaire|pleures|pleurit|pneumothorax|fibrose pulmon|bronchectas|hemopty|pneumolog|insuffisance respiratoire)' then
    return 'Pneumologie';
  end if;

  if t ~ '(cirrhose|hepatit|pancreatit|maladie de crohn|rectocolite|rchu|hemorragie digest|ulcere gastro|gastrit|reflux gastro|oesophag|gastro enter|gastroenter|colite|hepatolog)' then
    return 'Gastro-entérologie';
  end if;

  if t ~ '(insuffisance renal|insuffisance renale|ira|irc|maladie renal chronique|glomerul|syndrome nephrot|syndrome nephrit|proteinurie|dialys|hemodialys|hyperkali|hyponatrem|nephrolog)' then
    return 'Néphrologie';
  end if;

  if t ~ '(polyarthrit|spondylarthrit|lupus|vascularit|goutte|rhumat|arthrite inflamm|connectivit)' then
    return 'Rhumatologie';
  end if;

  if t ~ '(diabet|acidocetose|hyperosmolaire|thyroid|hyperthy|hypothy|surrenal|cushing|addison|hypophys|endocrin)' then
    return 'Endocrinologie - Diabétologie';
  end if;

  if t ~ '(leucemi|lymphome|myelome|anemie hemolyt|aplasie|thrombopen|hemophil|drpanocyt|drepanocyt|hematolog)' then
    return 'Hématologie';
  end if;

  if t ~ '(cancer|carcinom|adenocarcinom|sarcome|metastas|chimiotherap|immunotherap|radiotherap|oncolog)' then
    return 'Oncologie';
  end if;

  if t ~ '(sepsis|septicem|infection.*(bacter|viral|fong)|vih|tuberculos|palud|endocardite infect|infectiolog|antibiotherapie)' then
    return 'Infectiologie';
  end if;

  if t ~ '(detresse respiratoire|choc (septique|hemorragique|cardiogenique|anaphylactique)|vasopresseur|noradrenalin|ventilation mecanique|intubation|reanimation|sofa|defaillance multiviscer)' then
    return 'Réanimation';
  end if;

  if t ~ '(anesthes|induction|intubation difficile|mallampati|rachianesthes|peridurale|bloc nerveux|curare|propofol)' then
    return 'Anesthésie';
  end if;

  if t ~ '(depression|episode depress|suicid|psychose|schizophren|bipol|attaque de panique|trouble anxieux|psychiatr)' then
    return 'Psychiatrie';
  end if;

  if t ~ '(otite|sinusite|amygdal|epistaxis|vertige peripher|surdit|laryng|pharyng|orl|oto rhino)' then
    return 'ORL';
  end if;

  if t ~ '(glaucome|cataract|retine|decollement retinal|uveite|conjonctivit|keratit|baisse acuite visuelle|ophtalm)' then
    return 'Ophtalmologie';
  end if;

  if t ~ '(eczema|psoriasis|urticaire|melanome|lesion cutan|eruption cutan|dermatit|dermatolog)' then
    return 'Dermatologie';
  end if;

  if t ~ '(scanner|tdm|irm|echograph|radiograph|imagerie medicale|radiolog|embolisation|biopsie guidee)'
     and t ~ '(interpret|conclusion|controle|bilan radiolog|imagerie)' then
    return 'Imagerie Médicale';
  end if;

  if t ~ '(nourrisson|nouveau ne|pediatr|bronchiolite|convulsion febrile|puericulture)'
     or coalesce(p_age_band,'') = '<18 ans' then
    return 'Pédiatrie';
  end if;

  -- Urgences n'est pas une catégorie de secours.
  if t ~ '(polytraum|triage|urgence vitale|arret cardio respiratoire|acr|intoxication aigue|noyade|electrisation)' then
    return 'Urgences';
  end if;

  if t ~ '(fievre prolongee|amaigrissement|asthenie.*bilan|maladie systemique|medecine interne)' then
    return 'Médecine interne';
  end if;

  return 'Autres cas cliniques';
end;
$$;

create or replace function public.clinical_case_apply_specialty_classification()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  inferred text;
  raw_normalized text;
begin
  inferred := public.clinical_case_classify_specialty(
    new.age_band,
    new.presentation,
    new.history,
    new.clinical_exam,
    new.complementary_exams,
    new.imaging_conclusion,
    new.assessment,
    new.plan,
    new.disposition
  );

  raw_normalized := lower(extensions.unaccent(coalesce(btrim(new.specialist_service),'')));

  if raw_normalized = '' or raw_normalized in ('autres', 'autres cas cliniques') then
    new.specialist_service := inferred;
    new.specialty_classification_source := 'semantic_rules';
    new.specialty_classification_confidence := case
      when inferred = 'Autres cas cliniques' then 0.200
      else 0.850
    end;
    new.specialty_classified_at := now();
  elsif raw_normalized in ('urgence', 'urgences')
        and inferred not in ('Urgences','Autres cas cliniques') then
    new.specialist_service := inferred;
    new.specialty_classification_source := 'semantic_rules';
    new.specialty_classification_confidence := 0.850;
    new.specialty_classified_at := now();
  elsif new.specialty_classification_source is null then
    new.specialty_classification_source := 'declared';
    new.specialty_classification_confidence := 1.000;
    new.specialty_classified_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_clinical_case_apply_specialty_classification
on public.clinical_case_posts;

create trigger trg_clinical_case_apply_specialty_classification
before insert or update of
  age_band,
  presentation,
  history,
  clinical_exam,
  complementary_exams,
  imaging_conclusion,
  assessment,
  plan,
  disposition,
  specialist_service
on public.clinical_case_posts
for each row
execute function public.clinical_case_apply_specialty_classification();

-- Reclassification immédiate des anciens cas sans catégorie ou rangés dans Autres.
update public.clinical_case_posts c
set specialist_service = public.clinical_case_classify_specialty(
      c.age_band,
      c.presentation,
      c.history,
      c.clinical_exam,
      c.complementary_exams,
      c.imaging_conclusion,
      c.assessment,
      c.plan,
      c.disposition
    ),
    specialty_classification_source = 'semantic_rules',
    specialty_classification_confidence = case
      when public.clinical_case_classify_specialty(
        c.age_band,
        c.presentation,
        c.history,
        c.clinical_exam,
        c.complementary_exams,
        c.imaging_conclusion,
        c.assessment,
        c.plan,
        c.disposition
      ) = 'Autres cas cliniques' then 0.200
      else 0.850
    end,
    specialty_classified_at = now(),
    updated_at = now()
where coalesce(btrim(c.specialist_service),'') = ''
   or lower(extensions.unaccent(btrim(c.specialist_service)))
      in ('autres','autres cas cliniques');

-- Les spécialités explicitement renseignées par le médecin restent prioritaires.
update public.clinical_case_posts
set specialty_classification_source = 'declared',
    specialty_classification_confidence = 1.000,
    specialty_classified_at = coalesce(specialty_classified_at, now())
where specialty_classification_source is null
  and coalesce(btrim(specialist_service),'') <> '';
