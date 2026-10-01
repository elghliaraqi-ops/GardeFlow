class ProfileAvatarOption {
  final String key;
  final String label;
  final String svgMarkup;

  const ProfileAvatarOption({
    required this.key,
    required this.label,
    required this.svgMarkup,
  });
}

const String _avatarMaleBrown = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#263C74"/><stop offset="1" stop-color="#64C9FF"/></linearGradient><linearGradient id="c" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#DCEBFA"/></linearGradient></defs><circle cx="64" cy="64" r="62" fill="url(#b)"/><circle cx="64" cy="53" r="29" fill="#F1B98E"/><path d="M35 47c3-26 19-35 34-33 14 1 26 10 28 26-8-8-16-10-24-9-13 1-19 8-38 16Z" fill="#4B281E"/><path d="M41 40c7-14 22-20 37-14 6 2 12 7 16 13-17-9-35-5-53 1Z" fill="#713B28"/><ellipse cx="53" cy="54" rx="4" ry="5" fill="#14243D"/><ellipse cx="76" cy="54" rx="4" ry="5" fill="#14243D"/><path d="M56 68c6 5 12 5 17 0" fill="none" stroke="#A94F4A" stroke-width="3" stroke-linecap="round"/><path d="M31 126c2-25 13-38 33-38s31 13 33 38" fill="url(#c)"/><path d="M54 88l10 15 10-15" fill="#54B9E8"/><path d="M48 94c1 11 4 20 8 32M80 94c-1 11-4 20-8 32" fill="none" stroke="#9BB4CC" stroke-width="3"/><path d="M53 100c-13 6-15 20-5 23 8 3 14-4 13-12" fill="none" stroke="#2C4866" stroke-width="3"/><circle cx="48" cy="122" r="5" fill="#2C4866"/></svg>''';

const String _avatarFemaleBrown = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#493A88"/><stop offset="1" stop-color="#E783B8"/></linearGradient><linearGradient id="c" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4EEFA"/></linearGradient></defs><circle cx="64" cy="64" r="62" fill="url(#b)"/><path d="M31 54c0-28 14-42 34-42 22 0 35 15 35 43 0 22-9 30-18 33H46c-9-4-15-13-15-34Z" fill="#5B3029"/><circle cx="64" cy="53" r="27" fill="#F2B98F"/><path d="M38 45c4-22 18-31 29-31 16 0 28 10 31 28-12-8-20-12-31-11-10 0-19 6-29 14Z" fill="#6D392C"/><ellipse cx="53" cy="55" rx="4" ry="5" fill="#19233A"/><ellipse cx="76" cy="55" rx="4" ry="5" fill="#19233A"/><path d="M56 68c6 5 12 5 17 0" fill="none" stroke="#B45B61" stroke-width="3" stroke-linecap="round"/><path d="M28 127c3-25 16-39 36-39 21 0 34 14 36 39" fill="url(#c)"/><path d="M53 89l11 14 11-14" fill="#5CC3EC"/><path d="M48 96c1 10 4 20 8 31M80 96c-1 10-4 20-8 31" fill="none" stroke="#9EB8CD" stroke-width="3"/><path d="M54 102c-11 6-13 17-5 21 8 3 14-3 13-11" fill="none" stroke="#304D68" stroke-width="3"/><circle cx="49" cy="122" r="5" fill="#304D68"/></svg>''';

const String _avatarHijab = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#124C76"/><stop offset="1" stop-color="#7DD6F5"/></linearGradient><linearGradient id="h" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#F6FAFF"/><stop offset="1" stop-color="#B7D6EC"/></linearGradient></defs><circle cx="64" cy="64" r="62" fill="url(#b)"/><path d="M27 126c3-37 5-76 18-96 6-9 13-14 20-14 19 0 32 24 35 57l3 53H27Z" fill="url(#h)"/><path d="M42 51c0-19 10-31 22-31 13 0 23 12 23 31 0 19-10 31-23 31-12 0-22-12-22-31Z" fill="#E6A879"/><path d="M38 49c2-23 12-35 26-35 15 0 26 13 27 37-8-12-17-17-27-17-10 0-18 5-26 15Z" fill="#D9ECF7"/><ellipse cx="54" cy="54" rx="4" ry="5" fill="#172B45"/><ellipse cx="75" cy="54" rx="4" ry="5" fill="#172B45"/><path d="M57 68c5 4 10 4 15 0" fill="none" stroke="#A95250" stroke-width="3" stroke-linecap="round"/><path d="M35 127c4-23 14-36 29-36 16 0 26 13 30 36" fill="#FFFFFF"/><path d="M53 93l11 13 11-13" fill="#4FB9E6"/><path d="M50 101c0 9 3 18 7 26M78 101c0 9-3 18-7 26" fill="none" stroke="#97B7CE" stroke-width="3"/><circle cx="50" cy="121" r="5" fill="#2A4864"/><path d="M55 105c-10 5-12 14-5 18" fill="none" stroke="#2A4864" stroke-width="3"/></svg>''';

const String _avatarFemaleGlasses = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#26375F"/><stop offset="1" stop-color="#55C5D8"/></linearGradient></defs><circle cx="64" cy="64" r="62" fill="url(#b)"/><path d="M31 57c0-29 13-43 33-43 22 0 35 16 35 44 0 20-8 29-17 33H46c-9-5-15-15-15-34Z" fill="#1D2534"/><circle cx="64" cy="54" r="27" fill="#DFA277"/><path d="M38 44c7-22 20-29 33-27 12 1 22 9 27 24-12-6-22-9-33-7-9 1-17 5-27 10Z" fill="#171D28"/><circle cx="53" cy="55" r="9" fill="none" stroke="#263C58" stroke-width="3"/><circle cx="76" cy="55" r="9" fill="none" stroke="#263C58" stroke-width="3"/><path d="M62 55h5" stroke="#263C58" stroke-width="3"/><circle cx="53" cy="55" r="3" fill="#101D30"/><circle cx="76" cy="55" r="3" fill="#101D30"/><path d="M57 69c5 4 10 4 15 0" fill="none" stroke="#A65355" stroke-width="3" stroke-linecap="round"/><path d="M28 127c3-25 16-39 36-39s33 14 36 39" fill="#F7FBFF"/><path d="M53 89l11 14 11-14" fill="#53C2E4"/><path d="M49 97c1 10 4 20 8 30M79 97c-1 10-4 20-8 30" fill="none" stroke="#9BB7CA" stroke-width="3"/><circle cx="49" cy="122" r="5" fill="#29465F"/><path d="M55 104c-10 4-13 14-6 18" fill="none" stroke="#29465F" stroke-width="3"/></svg>''';

const String _avatarMasked = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#123A6A"/><stop offset="1" stop-color="#3FC9E8"/></linearGradient></defs><circle cx="64" cy="64" r="62" fill="url(#b)"/><circle cx="64" cy="53" r="28" fill="#DCA67C"/><path d="M36 42c5-20 17-29 30-29 15 0 27 10 31 29-10-7-21-10-31-9-10 0-20 4-30 9Z" fill="#342C2B"/><path d="M43 49h42v25c-5 8-12 12-21 12-9 0-16-4-21-12V49Z" fill="#B7ECF7"/><path d="M44 54c13 7 27 7 40 0M45 63c12 6 25 6 38 0" fill="none" stroke="#83CEDD" stroke-width="2"/><ellipse cx="53" cy="49" rx="4" ry="5" fill="#152943"/><ellipse cx="76" cy="49" rx="4" ry="5" fill="#152943"/><path d="M32 127c3-25 14-39 32-39 19 0 30 14 33 39" fill="#EDF8FC"/><path d="M51 90l13 15 13-15" fill="#43BDE5"/><path d="M48 98c1 10 4 20 8 29M80 98c-1 10-4 20-8 29" fill="none" stroke="#93B5C9" stroke-width="3"/><path d="M47 23h34v16H47z" rx="8" fill="#365D83"/><circle cx="64" cy="31" r="5" fill="#EFFAFF"/><path d="M61 31h6M64 28v6" stroke="#45BEE8" stroke-width="2"/></svg>''';

const String _avatarCurly = r'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#513773"/><stop offset="1" stop-color="#3DBBD0"/></linearGradient></defs><circle cx="64" cy="64" r="62" fill="url(#b)"/><circle cx="64" cy="54" r="27" fill="#B97955"/><path d="M34 45c0-20 13-34 30-34 17 0 31 13 31 34-4-4-8-7-13-9-2 6-7 7-11 2-3 5-8 6-12 1-4 5-9 4-12-1-4 3-8 5-13 7Z" fill="#252130"/><circle cx="43" cy="31" r="9" fill="#252130"/><circle cx="55" cy="22" r="10" fill="#252130"/><circle cx="69" cy="21" r="10" fill="#252130"/><circle cx="84" cy="28" r="10" fill="#252130"/><ellipse cx="53" cy="55" rx="4" ry="5" fill="#172239"/><ellipse cx="76" cy="55" rx="4" ry="5" fill="#172239"/><path d="M56 69c6 5 12 5 17 0" fill="none" stroke="#8D4045" stroke-width="3" stroke-linecap="round"/><path d="M29 127c3-25 16-39 35-39 20 0 33 14 36 39" fill="#F7FBFF"/><path d="M53 89l11 14 11-14" fill="#4EC0E0"/><path d="M49 97c1 10 4 20 8 30M79 97c-1 10-4 20-8 30" fill="none" stroke="#9AB5CA" stroke-width="3"/><circle cx="49" cy="122" r="5" fill="#2A4760"/><path d="M55 104c-10 5-12 15-5 18" fill="none" stroke="#2A4760" stroke-width="3"/></svg>''';

const List<ProfileAvatarOption> kProfileAvatarOptions = [
  ProfileAvatarOption(key: 'gamer_doctor_m_01', label: 'Avatar 1', svgMarkup: _avatarMaleBrown),
  ProfileAvatarOption(key: 'gamer_doctor_f_01', label: 'Avatar 2', svgMarkup: _avatarFemaleBrown),
  ProfileAvatarOption(key: 'gamer_doctor_hijab_01', label: 'Avatar 3', svgMarkup: _avatarHijab),
  ProfileAvatarOption(key: 'gamer_doctor_f_02', label: 'Avatar 4', svgMarkup: _avatarFemaleGlasses),
  ProfileAvatarOption(key: 'gamer_doctor_m_02', label: 'Avatar 5', svgMarkup: _avatarMasked),
  ProfileAvatarOption(key: 'gamer_doctor_m_03', label: 'Avatar 6', svgMarkup: _avatarCurly),
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
