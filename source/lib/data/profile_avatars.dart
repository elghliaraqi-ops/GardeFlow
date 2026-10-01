class ProfileAvatarOption {
  final String key;
  final String label;
  final String assetPath;

  const ProfileAvatarOption({
    required this.key,
    required this.label,
    required this.assetPath,
  });
}

const List<ProfileAvatarOption> kProfileAvatarOptions = [
  ProfileAvatarOption(
    key: 'gamer_doctor_f_01',
    label: 'Avatar 1',
    assetPath: 'assets/avatars/gamer_doctor_f_01.webp',
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_m_01',
    label: 'Avatar 2',
    assetPath: 'assets/avatars/gamer_doctor_m_01.webp',
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_hijab_01',
    label: 'Avatar 3',
    assetPath: 'assets/avatars/gamer_doctor_hijab_01.webp',
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_f_02',
    label: 'Avatar 4',
    assetPath: 'assets/avatars/gamer_doctor_f_02.webp',
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_m_03',
    label: 'Avatar 5',
    assetPath: 'assets/avatars/gamer_doctor_m_03.webp',
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_m_02',
    label: 'Avatar 6',
    assetPath: 'assets/avatars/gamer_doctor_m_02.webp',
  ),
];

ProfileAvatarOption? profileAvatarByKey(String? key) {
  if (key == null || key.trim().isEmpty) return null;
  for (final option in kProfileAvatarOptions) {
    if (option.key == key) return option;
  }
  return null;
}

bool isProfileAvatarKeyAllowed(String? key) {
  if (key == null || key.trim().isEmpty) return true;
  return profileAvatarByKey(key) != null;
}
