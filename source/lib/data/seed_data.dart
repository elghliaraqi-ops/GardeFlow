import '../models/app_user.dart';
import '../models/directory_contact.dart';
import '../theme/app_theme.dart';
import 'hospitals.dart';

/// Compte administrateur de démonstration. Le mot de passe n'est jamais stocké
/// dans AppUser : seul son hash salé est conservé dans l'état persistant.
const String kAdminPhone = '0600000090';
const String kAdminPasswordSalt = 'huim6-admin-seed-v5';
const String kAdminPasswordHash = '421aabd8b7f8a1593a6f6dd312ae7baa9b6df878268ed8bac984fe5be24ee535';

AppUser buildSeedAdmin() {
  return AppUser(
    id: 'local-admin',
    nom: 'Administrateur',
    prenom: 'Système',
    phone: kAdminPhone,
    passwordSalt: kAdminPasswordSalt,
    passwordHash: kAdminPasswordHash,
    service: 'Direction / Coordination',
    grade: MedicalGrade.junior,
    hospital: 'Tous établissements',
    role: UserRole.admin,
  );
}

List<DirectorySection> buildSeedDirectory() {
  return [
    DirectorySection(
      id: kDirectoryCategoryJuniors,
      label: directoryCategoryLabel(kDirectoryCategoryJuniors),
      color: AppColors.serviceJour,
      textColor: AppColors.serviceJourText,
      contacts: [
        DirectoryContact(
          name: 'Dr. Amel Haddad',
          phone: '+33612345601',
          hospital: kHospitals[0],
          categoryId: kDirectoryCategoryJuniors,
        ),
        DirectoryContact(
          name: 'Dr. Karim Bensalem',
          phone: '+33612345602',
          hospital: kHospitals[1],
          categoryId: kDirectoryCategoryJuniors,
        ),
      ],
    ),
    DirectorySection(
      id: kDirectoryCategorySeniors,
      label: directoryCategoryLabel(kDirectoryCategorySeniors),
      color: AppColors.service24h,
      textColor: AppColors.service24hText,
      contacts: [
        DirectoryContact(
          name: 'Dr. Nadia Rahal',
          phone: '+33612345610',
          hospital: kHospitals[0],
          categoryId: kDirectoryCategorySeniors,
        ),
        DirectoryContact(
          name: 'Dr. Yacine Meziane',
          phone: '+33612345611',
          hospital: kHospitals[2],
          categoryId: kDirectoryCategorySeniors,
        ),
      ],
    ),
    DirectorySection(
      id: kDirectoryCategoryNurses,
      label: directoryCategoryLabel(kDirectoryCategoryNurses),
      color: AppColors.conge,
      textColor: AppColors.congeText,
      contacts: [
        DirectoryContact(
          name: 'Sofia Belkacem',
          phone: '+33612345620',
          hospital: kHospitals[0],
          categoryId: kDirectoryCategoryNurses,
        ),
        DirectoryContact(
          name: 'Mehdi Ouali',
          phone: '+33612345621',
          hospital: kHospitals[1],
          categoryId: kDirectoryCategoryNurses,
        ),
      ],
    ),
    DirectorySection(
      id: kDirectoryCategoryFleet,
      label: directoryCategoryLabel(kDirectoryCategoryFleet),
      color: AppColors.urgJour,
      textColor: AppColors.urgJourText,
      contacts: [
        DirectoryContact(
          name: 'Véhicule 1 — Astreinte',
          phone: '+33612345630',
          hospital: kHospitals[0],
          categoryId: kDirectoryCategoryFleet,
        ),
        DirectoryContact(
          name: 'Ambulance A',
          phone: '+33612345631',
          hospital: kHospitals[1],
          categoryId: kDirectoryCategoryFleet,
        ),
      ],
    ),
    DirectorySection(
      id: kDirectoryCategoryMajorsSupervisors,
      label: directoryCategoryLabel(kDirectoryCategoryMajorsSupervisors),
      color: AppColors.urgNuit,
      textColor: AppColors.urgNuitText,
      contacts: [
        DirectoryContact(
          name: 'Fatima Zerrouki',
          phone: '+33612345640',
          hospital: kHospitals[0],
          categoryId: kDirectoryCategoryMajorsSupervisors,
        ),
        DirectoryContact(
          name: 'Omar Cherif',
          phone: '+33612345650',
          hospital: kHospitals[2],
          categoryId: kDirectoryCategoryMajorsSupervisors,
        ),
      ],
    ),
    DirectorySection(
      id: kDirectoryCategoryExtensions,
      label: directoryCategoryLabel(kDirectoryCategoryExtensions),
      color: AppColors.serviceNuit,
      textColor: AppColors.serviceNuitText,
      contacts: [
        DirectoryContact(
          name: 'Standard / Accueil',
          phone: '1000',
          hospital: kHospitals[0],
          categoryId: kDirectoryCategoryExtensions,
        ),
      ],
    ),
  ];
}
