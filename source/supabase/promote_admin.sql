-- Après avoir créé le compte administrateur depuis l'application,
-- remplacez le numéro ci-dessous puis exécutez ce script.
-- IMPORTANT : le rôle admin est indépendant du grade médical.
-- Cette commande ne modifie ni fonction ni medical_grade.
update public.profiles
set role = 'admin'
where phone = '+212600000090';
