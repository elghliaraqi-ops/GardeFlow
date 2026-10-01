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
  ProfileAvatarOption(
    key: 'avatar_7',
    label: 'Avatar 7',
    assetPath: 'assets/avatars/avatar_7.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_8',
    label: 'Avatar 8',
    assetPath: 'assets/avatars/avatar_8.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_9',
    label: 'Avatar 9',
    assetPath: 'assets/avatars/avatar_9.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_10',
    label: 'Avatar 10',
    assetPath: 'assets/avatars/avatar_10.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_11',
    label: 'Avatar 11',
    assetPath: 'assets/avatars/avatar_11.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_12',
    label: 'Avatar 12',
    assetPath: 'assets/avatars/avatar_12.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_13',
    label: 'Avatar 13',
    assetPath: 'assets/avatars/avatar_13.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_14',
    label: 'Avatar 14',
    assetPath: 'assets/avatars/avatar_14.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_15',
    label: 'Avatar 15',
    assetPath: 'assets/avatars/avatar_15.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_16',
    label: 'Avatar 16',
    assetPath: 'assets/avatars/avatar_16.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_17',
    label: 'Avatar 17',
    assetPath: 'assets/avatars/avatar_17.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_18',
    label: 'Avatar 18',
    assetPath: 'assets/avatars/avatar_18.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_19',
    label: 'Avatar 19',
    assetPath: 'assets/avatars/avatar_19.webp',
  ),
  ProfileAvatarOption(
    key: 'avatar_20',
    label: 'Avatar 20',
    assetPath: 'assets/avatars/avatar_20.webp',
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
