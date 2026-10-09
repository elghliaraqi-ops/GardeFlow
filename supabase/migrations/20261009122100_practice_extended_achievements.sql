-- Practice achievements, 2026-10-09. Retain every existing key and unlock date.
-- New rewards are grounded in existing persisted clinical, daily and simulation events.
insert into public.practice_achievements(key,name,description,metric,threshold,icon,sort_order)
values
 ('v2_patients_2','2 observations documentées','Atteindre 2 observations documentées sur l’activité enregistrée de votre compte.','patients',2,'clinical_notes',1000),
 ('v2_patients_3','3 observations documentées','Atteindre 3 observations documentées sur l’activité enregistrée de votre compte.','patients',3,'clinical_notes',1001),
 ('v2_patients_5','5 observations documentées','Atteindre 5 observations documentées sur l’activité enregistrée de votre compte.','patients',5,'clinical_notes',1002),
 ('v2_patients_15','15 observations documentées','Atteindre 15 observations documentées sur l’activité enregistrée de votre compte.','patients',15,'clinical_notes',1003),
 ('v2_patients_35','35 observations documentées','Atteindre 35 observations documentées sur l’activité enregistrée de votre compte.','patients',35,'clinical_notes',1004),
 ('v2_patients_75','75 observations documentées','Atteindre 75 observations documentées sur l’activité enregistrée de votre compte.','patients',75,'clinical_notes',1005),
 ('v2_patients_150','150 observations documentées','Atteindre 150 observations documentées sur l’activité enregistrée de votre compte.','patients',150,'clinical_notes',1006),
 ('v2_patients_350','350 observations documentées','Atteindre 350 observations documentées sur l’activité enregistrée de votre compte.','patients',350,'clinical_notes',1007),
 ('v2_complete_1','1 observations complètes','Atteindre 1 observations complètes sur l’activité enregistrée de votre compte.','complete',1,'verified',1008),
 ('v2_complete_3','3 observations complètes','Atteindre 3 observations complètes sur l’activité enregistrée de votre compte.','complete',3,'verified',1009),
 ('v2_complete_5','5 observations complètes','Atteindre 5 observations complètes sur l’activité enregistrée de votre compte.','complete',5,'verified',1010),
 ('v2_complete_10','10 observations complètes','Atteindre 10 observations complètes sur l’activité enregistrée de votre compte.','complete',10,'verified',1011),
 ('v2_complete_25','25 observations complètes','Atteindre 25 observations complètes sur l’activité enregistrée de votre compte.','complete',25,'verified',1012),
 ('v2_complete_50','50 observations complètes','Atteindre 50 observations complètes sur l’activité enregistrée de votre compte.','complete',50,'verified',1013),
 ('v2_complete_250','250 observations complètes','Atteindre 250 observations complètes sur l’activité enregistrée de votre compte.','complete',250,'verified',1014),
 ('v2_avis_1','1 avis spécialisés documentés','Atteindre 1 avis spécialisés documentés sur l’activité enregistrée de votre compte.','specialist',1,'groups',1015),
 ('v2_avis_3','3 avis spécialisés documentés','Atteindre 3 avis spécialisés documentés sur l’activité enregistrée de votre compte.','specialist',3,'groups',1016),
 ('v2_avis_5','5 avis spécialisés documentés','Atteindre 5 avis spécialisés documentés sur l’activité enregistrée de votre compte.','specialist',5,'groups',1017),
 ('v2_avis_20','20 avis spécialisés documentés','Atteindre 20 avis spécialisés documentés sur l’activité enregistrée de votre compte.','specialist',20,'groups',1018),
 ('v2_avis_30','30 avis spécialisés documentés','Atteindre 30 avis spécialisés documentés sur l’activité enregistrée de votre compte.','specialist',30,'groups',1019),
 ('v2_avis_50','50 avis spécialisés documentés','Atteindre 50 avis spécialisés documentés sur l’activité enregistrée de votre compte.','specialist',50,'groups',1020),
 ('v2_gardes_1','1 gardes Urgences documentées','Atteindre 1 gardes Urgences documentées sur l’activité enregistrée de votre compte.','guards',1,'calendar_month',1021),
 ('v2_gardes_3','3 gardes Urgences documentées','Atteindre 3 gardes Urgences documentées sur l’activité enregistrée de votre compte.','guards',3,'calendar_month',1022),
 ('v2_gardes_5','5 gardes Urgences documentées','Atteindre 5 gardes Urgences documentées sur l’activité enregistrée de votre compte.','guards',5,'calendar_month',1023),
 ('v2_gardes_10','10 gardes Urgences documentées','Atteindre 10 gardes Urgences documentées sur l’activité enregistrée de votre compte.','guards',10,'calendar_month',1024),
 ('v2_gardes_15','15 gardes Urgences documentées','Atteindre 15 gardes Urgences documentées sur l’activité enregistrée de votre compte.','guards',15,'calendar_month',1025),
 ('v2_gardes_50','50 gardes Urgences documentées','Atteindre 50 gardes Urgences documentées sur l’activité enregistrée de votre compte.','guards',50,'calendar_month',1026),
 ('v2_série_2','2 gardes consécutives documentées','Atteindre 2 gardes consécutives documentées sur l’activité enregistrée de votre compte.','streak',2,'local_fire_department',1027),
 ('v2_série_4','4 gardes consécutives documentées','Atteindre 4 gardes consécutives documentées sur l’activité enregistrée de votre compte.','streak',4,'local_fire_department',1028),
 ('v2_série_7','7 gardes consécutives documentées','Atteindre 7 gardes consécutives documentées sur l’activité enregistrée de votre compte.','streak',7,'local_fire_department',1029),
 ('v2_série_15','15 gardes consécutives documentées','Atteindre 15 gardes consécutives documentées sur l’activité enregistrée de votre compte.','streak',15,'local_fire_department',1030),
 ('v2_série_20','20 gardes consécutives documentées','Atteindre 20 gardes consécutives documentées sur l’activité enregistrée de votre compte.','streak',20,'local_fire_department',1031),
 ('v2_série_25','25 gardes consécutives documentées','Atteindre 25 gardes consécutives documentées sur l’activité enregistrée de votre compte.','streak',25,'local_fire_department',1032),
 ('v2_qcm_2','2 QCM de cas répondus','Atteindre 2 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',2,'quiz',1033),
 ('v2_qcm_3','3 QCM de cas répondus','Atteindre 3 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',3,'quiz',1034),
 ('v2_qcm_5','5 QCM de cas répondus','Atteindre 5 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',5,'quiz',1035),
 ('v2_qcm_15','15 QCM de cas répondus','Atteindre 15 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',15,'quiz',1036),
 ('v2_qcm_35','35 QCM de cas répondus','Atteindre 35 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',35,'quiz',1037),
 ('v2_qcm_75','75 QCM de cas répondus','Atteindre 75 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',75,'quiz',1038),
 ('v2_qcm_150','150 QCM de cas répondus','Atteindre 150 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',150,'quiz',1039),
 ('v2_qcm_250','250 QCM de cas répondus','Atteindre 250 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',250,'quiz',1040),
 ('v2_qcm_500','500 QCM de cas répondus','Atteindre 500 QCM de cas répondus sur l’activité enregistrée de votre compte.','qcm_answered',500,'quiz',1041),
 ('v2_réussite_1','1 bonnes réponses QCM','Atteindre 1 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',1,'check_circle',1042),
 ('v2_réussite_3','3 bonnes réponses QCM','Atteindre 3 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',3,'check_circle',1043),
 ('v2_réussite_5','5 bonnes réponses QCM','Atteindre 5 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',5,'check_circle',1044),
 ('v2_réussite_15','15 bonnes réponses QCM','Atteindre 15 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',15,'check_circle',1045),
 ('v2_réussite_35','35 bonnes réponses QCM','Atteindre 35 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',35,'check_circle',1046),
 ('v2_réussite_75','75 bonnes réponses QCM','Atteindre 75 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',75,'check_circle',1047),
 ('v2_réussite_150','150 bonnes réponses QCM','Atteindre 150 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',150,'check_circle',1048),
 ('v2_réussite_250','250 bonnes réponses QCM','Atteindre 250 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',250,'check_circle',1049),
 ('v2_réussite_500','500 bonnes réponses QCM','Atteindre 500 bonnes réponses QCM sur l’activité enregistrée de votre compte.','qcm_correct',500,'check_circle',1050),
 ('v2_xp_50','50 XP Practice clinique','Atteindre 50 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',50,'trending_up',1051),
 ('v2_xp_100','100 XP Practice clinique','Atteindre 100 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',100,'trending_up',1052),
 ('v2_xp_250','250 XP Practice clinique','Atteindre 250 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',250,'trending_up',1053),
 ('v2_xp_750','750 XP Practice clinique','Atteindre 750 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',750,'trending_up',1054),
 ('v2_xp_1500','1 500 XP Practice clinique','Atteindre 1500 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',1500,'trending_up',1055),
 ('v2_xp_5000','5 000 XP Practice clinique','Atteindre 5000 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',5000,'trending_up',1056),
 ('v2_xp_10000','10 000 XP Practice clinique','Atteindre 10000 XP Practice clinique sur l’activité enregistrée de votre compte.','xp',10000,'trending_up',1057),
 ('v2_hors-garde_1','1 cas hors garde documentés','Atteindre 1 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',1,'clinical_notes',1058),
 ('v2_hors-garde_3','3 cas hors garde documentés','Atteindre 3 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',3,'clinical_notes',1059),
 ('v2_hors-garde_5','5 cas hors garde documentés','Atteindre 5 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',5,'clinical_notes',1060),
 ('v2_hors-garde_10','10 cas hors garde documentés','Atteindre 10 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',10,'clinical_notes',1061),
 ('v2_hors-garde_20','20 cas hors garde documentés','Atteindre 20 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',20,'clinical_notes',1062),
 ('v2_hors-garde_50','50 cas hors garde documentés','Atteindre 50 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',50,'clinical_notes',1063),
 ('v2_hors-garde_100','100 cas hors garde documentés','Atteindre 100 cas hors garde documentés sur l’activité enregistrée de votre compte.','standalone_cases',100,'clinical_notes',1064),
 ('v2_quotidien_1','1 défis quotidiens terminés','Atteindre 1 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',1,'calendar_month',1065),
 ('v2_quotidien_3','3 défis quotidiens terminés','Atteindre 3 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',3,'calendar_month',1066),
 ('v2_quotidien_5','5 défis quotidiens terminés','Atteindre 5 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',5,'calendar_month',1067),
 ('v2_quotidien_7','7 défis quotidiens terminés','Atteindre 7 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',7,'calendar_month',1068),
 ('v2_quotidien_10','10 défis quotidiens terminés','Atteindre 10 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',10,'calendar_month',1069),
 ('v2_quotidien_20','20 défis quotidiens terminés','Atteindre 20 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',20,'calendar_month',1070),
 ('v2_quotidien_30','30 défis quotidiens terminés','Atteindre 30 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',30,'calendar_month',1071),
 ('v2_quotidien_50','50 défis quotidiens terminés','Atteindre 50 défis quotidiens terminés sur l’activité enregistrée de votre compte.','daily_completed',50,'calendar_month',1072),
 ('v2_sans-faute_1','1 défis parfaits (10/10)','Atteindre 1 défis parfaits (10/10) sur l’activité enregistrée de votre compte.','daily_perfect',1,'workspace_premium',1073),
 ('v2_sans-faute_2','2 défis parfaits (10/10)','Atteindre 2 défis parfaits (10/10) sur l’activité enregistrée de votre compte.','daily_perfect',2,'workspace_premium',1074),
 ('v2_sans-faute_3','3 défis parfaits (10/10)','Atteindre 3 défis parfaits (10/10) sur l’activité enregistrée de votre compte.','daily_perfect',3,'workspace_premium',1075),
 ('v2_sans-faute_5','5 défis parfaits (10/10)','Atteindre 5 défis parfaits (10/10) sur l’activité enregistrée de votre compte.','daily_perfect',5,'workspace_premium',1076),
 ('v2_sans-faute_10','10 défis parfaits (10/10)','Atteindre 10 défis parfaits (10/10) sur l’activité enregistrée de votre compte.','daily_perfect',10,'workspace_premium',1077),
 ('v2_sans-faute_20','20 défis parfaits (10/10)','Atteindre 20 défis parfaits (10/10) sur l’activité enregistrée de votre compte.','daily_perfect',20,'workspace_premium',1078),
 ('v2_score-jour_25','25 bonnes réponses aux défis quotidiens','Atteindre 25 bonnes réponses aux défis quotidiens sur l’activité enregistrée de votre compte.','daily_score_total',25,'verified',1079),
 ('v2_score-jour_50','50 bonnes réponses aux défis quotidiens','Atteindre 50 bonnes réponses aux défis quotidiens sur l’activité enregistrée de votre compte.','daily_score_total',50,'verified',1080),
 ('v2_score-jour_100','100 bonnes réponses aux défis quotidiens','Atteindre 100 bonnes réponses aux défis quotidiens sur l’activité enregistrée de votre compte.','daily_score_total',100,'verified',1081),
 ('v2_score-jour_250','250 bonnes réponses aux défis quotidiens','Atteindre 250 bonnes réponses aux défis quotidiens sur l’activité enregistrée de votre compte.','daily_score_total',250,'verified',1082),
 ('v2_score-jour_500','500 bonnes réponses aux défis quotidiens','Atteindre 500 bonnes réponses aux défis quotidiens sur l’activité enregistrée de votre compte.','daily_score_total',500,'verified',1083),
 ('v2_progressif_1','1 cas progressifs complets générés','Atteindre 1 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',1,'school',1084),
 ('v2_progressif_2','2 cas progressifs complets générés','Atteindre 2 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',2,'school',1085),
 ('v2_progressif_3','3 cas progressifs complets générés','Atteindre 3 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',3,'school',1086),
 ('v2_progressif_5','5 cas progressifs complets générés','Atteindre 5 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',5,'school',1087),
 ('v2_progressif_10','10 cas progressifs complets générés','Atteindre 10 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',10,'school',1088),
 ('v2_progressif_20','20 cas progressifs complets générés','Atteindre 20 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',20,'school',1089),
 ('v2_progressif_50','50 cas progressifs complets générés','Atteindre 50 cas progressifs complets générés sur l’activité enregistrée de votre compte.','progressive_generated',50,'school',1090),
 ('v2_spécialités_2','2 spécialités explorées en simulation','Atteindre 2 spécialités explorées en simulation sur l’activité enregistrée de votre compte.','generated_specialties',2,'public',1091),
 ('v2_spécialités_3','3 spécialités explorées en simulation','Atteindre 3 spécialités explorées en simulation sur l’activité enregistrée de votre compte.','generated_specialties',3,'public',1092),
 ('v2_spécialités_5','5 spécialités explorées en simulation','Atteindre 5 spécialités explorées en simulation sur l’activité enregistrée de votre compte.','generated_specialties',5,'public',1093),
 ('v2_spécialités_7','7 spécialités explorées en simulation','Atteindre 7 spécialités explorées en simulation sur l’activité enregistrée de votre compte.','generated_specialties',7,'public',1094),
 ('v2_spécialités_10','10 spécialités explorées en simulation','Atteindre 10 spécialités explorées en simulation sur l’activité enregistrée de votre compte.','generated_specialties',10,'public',1095),
 ('v2_spécialités_15','15 spécialités explorées en simulation','Atteindre 15 spécialités explorées en simulation sur l’activité enregistrée de votre compte.','generated_specialties',15,'public',1096),
 ('v2_assiduité_2','2 jours de défis réussis consécutifs','Atteindre 2 jours de défis réussis consécutifs sur l’activité enregistrée de votre compte.','daily_streak',2,'local_fire_department',1097),
 ('v2_assiduité_3','3 jours de défis réussis consécutifs','Atteindre 3 jours de défis réussis consécutifs sur l’activité enregistrée de votre compte.','daily_streak',3,'local_fire_department',1098),
 ('v2_assiduité_5','5 jours de défis réussis consécutifs','Atteindre 5 jours de défis réussis consécutifs sur l’activité enregistrée de votre compte.','daily_streak',5,'local_fire_department',1099),
 ('v2_assiduité_7','7 jours de défis réussis consécutifs','Atteindre 7 jours de défis réussis consécutifs sur l’activité enregistrée de votre compte.','daily_streak',7,'local_fire_department',1100),
 ('v2_assiduité_14','14 jours de défis réussis consécutifs','Atteindre 14 jours de défis réussis consécutifs sur l’activité enregistrée de votre compte.','daily_streak',14,'local_fire_department',1101),
 ('v2_assiduité_30','30 jours de défis réussis consécutifs','Atteindre 30 jours de défis réussis consécutifs sur l’activité enregistrée de votre compte.','daily_streak',30,'local_fire_department',1102),
 ('v2_précision50_60','60% de précision (50 QCM min.)','Atteindre 60% de réussite avec au moins 50 QCM de cas répondus.','qcm_accuracy_50',60,'quiz',1103),
 ('v2_précision50_70','70% de précision (50 QCM min.)','Atteindre 70% de réussite avec au moins 50 QCM de cas répondus.','qcm_accuracy_50',70,'quiz',1104),
 ('v2_précision50_80','80% de précision (50 QCM min.)','Atteindre 80% de réussite avec au moins 50 QCM de cas répondus.','qcm_accuracy_50',80,'quiz',1105),
 ('v2_précision50_90','90% de précision (50 QCM min.)','Atteindre 90% de réussite avec au moins 50 QCM de cas répondus.','qcm_accuracy_50',90,'quiz',1106),
 ('v2_précision50_95','95% de précision (50 QCM min.)','Atteindre 95% de réussite avec au moins 50 QCM de cas répondus.','qcm_accuracy_50',95,'quiz',1107),
 ('v2_précision100_60','60% de précision (100 QCM min.)','Atteindre 60% de réussite avec au moins 100 QCM de cas répondus.','qcm_accuracy_100',60,'workspace_premium',1108),
 ('v2_précision100_70','70% de précision (100 QCM min.)','Atteindre 70% de réussite avec au moins 100 QCM de cas répondus.','qcm_accuracy_100',70,'workspace_premium',1109),
 ('v2_précision100_80','80% de précision (100 QCM min.)','Atteindre 80% de réussite avec au moins 100 QCM de cas répondus.','qcm_accuracy_100',80,'workspace_premium',1110),
 ('v2_précision100_90','90% de précision (100 QCM min.)','Atteindre 90% de réussite avec au moins 100 QCM de cas répondus.','qcm_accuracy_100',90,'workspace_premium',1111),
 ('v2_précision100_95','95% de précision (100 QCM min.)','Atteindre 95% de réussite avec au moins 100 QCM de cas répondus.','qcm_accuracy_100',95,'workspace_premium',1112)
on conflict(key) do nothing;

create or replace function public.practice_refresh_my_achievements()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
 uid uuid := (select auth.uid());
 a record;
 progress_value integer;
 total_patients integer := 0;
 total_complete integer := 0;
 total_specialist integer := 0;
 total_guards integer := 0;
 current_streak integer := 0;
 qcm_answered integer := 0;
 qcm_correct integer := 0;
 clinical_xp integer := 0;
 combined_xp integer := 0;
 standalone_cases integer := 0;
 daily_completed integer := 0;
 daily_perfect integer := 0;
 daily_score_total integer := 0;
 daily_streak integer := 0;
 progressive_generated integer := 0;
 generated_specialties integer := 0;
 accuracy_50 integer := 0;
 accuracy_100 integer := 0;
begin
 if uid is null then raise exception 'Authentification requise.'; end if;

 select count(*)::int,
  count(*) filter(where public.practice_case_is_complete(pc))::int,
  count(*) filter(where pc.specialist_opinion_requested)::int,
  count(distinct pc.guard_id)::int,
  coalesce(sum(public.practice_case_xp(pc)),0)::int
 into total_patients,total_complete,total_specialist,total_guards,clinical_xp
 from public.practice_cases pc
 where pc.user_id=uid and pc.encounter_context='emergency_guard'
  and pc.is_draft=false and public.practice_case_is_valid(pc);

 select count(*)::int into standalone_cases
 from public.practice_cases pc
 where pc.user_id=uid and pc.encounter_context='standalone'
  and pc.is_draft=false and public.practice_case_is_valid(pc);

 select count(*)::int,count(*) filter(where qa.is_correct)::int
 into qcm_answered,qcm_correct
 from private.clinical_case_qcm_response_events qa where qa.stats_user_id=uid;

 select count(*)::int,
        count(*) filter(where score=10)::int,
        coalesce(sum(score),0)::int
 into daily_completed,daily_perfect,daily_score_total
 from public.practice_daily_attempts da
 where da.user_id=uid and da.completed_at is not null;

 select coalesce(max(streak_length),0)::int into daily_streak
 from (
   select max(challenge_date) as last_day, count(*) as streak_length
   from (
     select day,day-row_number() over(order by day)::int as series
     from (
       select distinct da.challenge_date as day
       from public.practice_daily_attempts da
       where da.user_id=uid and da.completed_at is not null
     ) days
   ) groups_of_days
   group by series
 ) runs
 where runs.last_day >= (now() at time zone 'Africa/Casablanca')::date - 1;

 select count(*)::int,count(distinct specialty)::int
 into progressive_generated,generated_specialties
 from public.practice_generated_cases gc
 where gc.owner_id=uid and gc.generation_status='ready';

 current_streak:=public.practice_current_streak(uid);
 combined_xp:=clinical_xp+qcm_answered*2+qcm_correct*3;
 accuracy_50:=case when qcm_answered>=50
  then floor(qcm_correct::numeric*100/greatest(qcm_answered,1))::int else 0 end;
 accuracy_100:=case when qcm_answered>=100
  then floor(qcm_correct::numeric*100/greatest(qcm_answered,1))::int else 0 end;

 for a in select * from public.practice_achievements loop
   progress_value:=case a.metric
     when 'patients' then total_patients
     when 'complete' then total_complete
     when 'specialist' then total_specialist
     when 'guards' then total_guards
     when 'streak' then current_streak
     when 'qcm_answered' then qcm_answered
     when 'qcm_correct' then qcm_correct
     when 'xp' then combined_xp
     when 'standalone_cases' then standalone_cases
     when 'daily_completed' then daily_completed
     when 'daily_perfect' then daily_perfect
     when 'daily_score_total' then daily_score_total
     when 'daily_streak' then daily_streak
     when 'progressive_generated' then progressive_generated
     when 'generated_specialties' then generated_specialties
     when 'qcm_accuracy_50' then accuracy_50
     when 'qcm_accuracy_100' then accuracy_100
     else 0 end;
   insert into public.user_practice_achievements(
    user_id,achievement_id,progress,unlocked_at,updated_at
   ) values (
    uid,a.id,progress_value,
    case when progress_value>=a.threshold then now() else null end,
    now()
   )
   on conflict(user_id,achievement_id) do update
   set progress=excluded.progress,
       unlocked_at=coalesce(public.user_practice_achievements.unlocked_at,excluded.unlocked_at),
       updated_at=now();
 end loop;
end;
$$;

comment on function public.practice_refresh_my_achievements() is
 'Recompute real achievements from scoped persisted user activities; preserve historic unlock timestamps.';
