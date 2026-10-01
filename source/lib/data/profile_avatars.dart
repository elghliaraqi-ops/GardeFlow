class ProfileAvatarOption {
  final String key;
  final String label;
  final String assetPath;
  final double circleScale;
  final double circleOffsetX;
  final double circleOffsetY;

  const ProfileAvatarOption({
    required this.key,
    required this.label,
    required this.assetPath,
    this.circleScale = 1.0,
    this.circleOffsetX = 0.0,
    this.circleOffsetY = 0.0,
  });
}

const List<ProfileAvatarOption> kProfileAvatarOptions = [
  ProfileAvatarOption(
    key: 'avatar_1',
    label: 'Avatar 1',
    assetPath: 'assets/avatars/gamer_doctor_m_01.webp',
    circleScale: 1.04,
    circleOffsetX: -0.10,
    circleOffsetY: 0.06,
  ),
  ProfileAvatarOption(
    key: 'avatar_2',
    label: 'Avatar 2',
    assetPath: 'assets/avatars/gamer_doctor_f_01.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_3',
    label: 'Avatar 3',
    assetPath: 'assets/avatars/gamer_doctor_hijab_01.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_4',
    label: 'Avatar 4',
    assetPath: 'assets/avatars/gamer_doctor_f_02.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_5',
    label: 'Avatar 5',
    assetPath: 'assets/avatars/gamer_doctor_m_02.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_6',
    label: 'Avatar 6',
    assetPath: 'assets/avatars/gamer_doctor_m_03.webp',
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
