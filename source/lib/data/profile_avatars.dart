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

enum _AvatarHairStyle { swept, long, hijab, glassesBob, surgicalCap, curls }

String _avatarSvg({
  required _AvatarHairStyle hairStyle,
  required String skinTop,
  required String skinBottom,
  required String hairTop,
  required String hairBottom,
  required String bgStart,
  required String bgEnd,
  String scrub = '#1769D2',
  String accent = '#34F4E7',
}) {
  final behindHair = switch (hairStyle) {
    _AvatarHairStyle.long => '''
      <path d="M70 106C66 55 88 25 128 25c43 0 65 31 59 83-3 29-14 43-28 52H96c-16-10-25-27-26-54Z" fill="url(#hair)"/>
      <path d="M78 83c-9 30-8 53 8 70" fill="none" stroke="#FFFFFF" stroke-opacity=".11" stroke-width="7" stroke-linecap="round"/>
      <path d="M178 80c9 31 7 54-9 72" fill="none" stroke="#080D1D" stroke-opacity=".18" stroke-width="8" stroke-linecap="round"/>
    ''',
    _AvatarHairStyle.glassesBob => '''
      <path d="M76 106C70 62 88 29 126 27c43-2 65 29 60 78-2 26-10 43-25 54H96c-14-10-20-29-20-53Z" fill="url(#hair)"/>
      <path d="M80 78c-4 32-1 55 13 72" fill="none" stroke="#FFFFFF" stroke-opacity=".09" stroke-width="6" stroke-linecap="round"/>
    ''',
    _AvatarHairStyle.hijab => '''
      <path d="M66 159c1-39 6-83 20-111 10-19 24-29 42-29 34 0 57 36 61 93l4 72H63l3-25Z" fill="url(#hijab)"/>
      <path d="M76 99c5-35 20-58 51-62 29 4 45 28 50 61-13-12-29-18-49-18-20 0-37 6-52 19Z" fill="#EEF5FF" fill-opacity=".82"/>
      <path d="M76 117c4 34 16 55 31 70M178 116c-3 34-13 55-29 72" fill="none" stroke="#89B7E0" stroke-opacity=".35" stroke-width="5" stroke-linecap="round"/>
    ''',
    _ => '',
  };

  final frontHair = switch (hairStyle) {
    _AvatarHairStyle.swept => '''
      <path d="M80 71c7-34 30-51 59-47 27 3 44 21 47 49-15-10-26-15-41-15-23 0-36 13-65 28 0-5 0-10 0-15Z" fill="url(#hair)"/>
      <path d="M98 51c18-17 45-21 66-7" fill="none" stroke="#FFD2B7" stroke-opacity=".18" stroke-width="7" stroke-linecap="round"/>
      <path d="M112 40c16-7 34-5 46 2" fill="none" stroke="#FFFFFF" stroke-opacity=".12" stroke-width="4" stroke-linecap="round"/>
    ''',
    _AvatarHairStyle.long => '''
      <path d="M77 72c8-35 29-51 57-48 30 3 47 22 51 51-15-11-29-16-44-16-21 0-37 10-64 27V72Z" fill="url(#hair)"/>
      <path d="M93 50c21-16 46-19 66-6" fill="none" stroke="#FFD8C0" stroke-opacity=".18" stroke-width="6" stroke-linecap="round"/>
    ''',
    _AvatarHairStyle.glassesBob => '''
      <path d="M79 73c7-34 28-50 56-47 28 3 45 21 49 48-15-9-29-14-44-14-22 0-37 11-61 26V73Z" fill="url(#hair)"/>
      <path d="M95 48c20-13 43-15 61-4" fill="none" stroke="#FFD9C1" stroke-opacity=".16" stroke-width="5" stroke-linecap="round"/>
    ''',
    _AvatarHairStyle.surgicalCap => '''
      <path d="M75 73c4-31 24-49 54-50 31 0 51 18 55 50-13-10-31-15-54-15-23 0-41 5-55 15Z" fill="url(#cap)"/>
      <path d="M84 51c24-12 58-12 88 0" fill="none" stroke="#FFFFFF" stroke-opacity=".25" stroke-width="5" stroke-linecap="round"/>
      <path d="M83 68c20-6 48-8 89-2" fill="none" stroke="#0B537D" stroke-opacity=".30" stroke-width="4" stroke-linecap="round"/>
      <path d="M176 70c10 9 14 19 9 32" fill="none" stroke="#0B537D" stroke-width="7" stroke-linecap="round"/>
    ''',
    _AvatarHairStyle.curls => '''
      <g fill="url(#hair)">
        <circle cx="90" cy="53" r="17"/><circle cx="107" cy="39" r="18"/><circle cx="128" cy="37" r="19"/>
        <circle cx="149" cy="39" r="18"/><circle cx="168" cy="51" r="17"/><circle cx="82" cy="68" r="15"/>
        <circle cx="101" cy="59" r="17"/><circle cx="124" cy="56" r="18"/><circle cx="148" cy="58" r="17"/><circle cx="174" cy="69" r="15"/>
      </g>
      <g fill="#FFFFFF" fill-opacity=".10">
        <circle cx="103" cy="35" r="6"/><circle cx="126" cy="33" r="6"/><circle cx="148" cy="37" r="5"/><circle cx="91" cy="52" r="5"/>
      </g>
    ''',
    _AvatarHairStyle.hijab => '',
  };

  final glasses = hairStyle == _AvatarHairStyle.glassesBob
      ? '''
        <g fill="none" stroke="#18243A" stroke-width="4">
          <ellipse cx="105" cy="101" rx="19" ry="16"/>
          <ellipse cx="151" cy="101" rx="19" ry="16"/>
          <path d="M124 101h8M86 98l-12-3M170 98l12-3" stroke-linecap="round"/>
        </g>
        <path d="M91 92c9-7 19-8 28-3" fill="none" stroke="#FFFFFF" stroke-opacity=".30" stroke-width="2" stroke-linecap="round"/>
      '''
      : '';

  final hijabFaceFrame = hairStyle == _AvatarHairStyle.hijab
      ? '''
        <path d="M83 87c6-34 22-50 45-50 24 0 40 17 46 50-12-10-27-15-46-15-18 0-33 5-45 15Z" fill="#F5F8FF"/>
      '''
      : '';

  return '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
    <defs>
      <radialGradient id="bg" cx="30%" cy="24%" r="90%">
        <stop offset="0" stop-color="$bgStart"/>
        <stop offset=".58" stop-color="$bgEnd"/>
        <stop offset="1" stop-color="#071423"/>
      </radialGradient>
      <linearGradient id="skin" x1=".15" y1=".08" x2=".86" y2=".94">
        <stop offset="0" stop-color="$skinTop"/>
        <stop offset=".58" stop-color="$skinTop"/>
        <stop offset="1" stop-color="$skinBottom"/>
      </linearGradient>
      <linearGradient id="skinShadow" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="$skinBottom" stop-opacity=".12"/>
        <stop offset="1" stop-color="$skinBottom" stop-opacity=".60"/>
      </linearGradient>
      <linearGradient id="hair" x1=".15" y1=".08" x2=".9" y2=".95">
        <stop stop-color="$hairTop"/><stop offset=".48" stop-color="$hairBottom"/><stop offset="1" stop-color="#111423"/>
      </linearGradient>
      <linearGradient id="coat" x1=".15" y1="0" x2=".84" y2="1">
        <stop stop-color="#FFFFFF"/><stop offset=".55" stop-color="#EDF5FF"/><stop offset="1" stop-color="#A7C5E4"/>
      </linearGradient>
      <linearGradient id="scrub" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#2F8BFF"/><stop offset="1" stop-color="$scrub"/>
      </linearGradient>
      <linearGradient id="metal" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#F9FDFF"/><stop offset=".28" stop-color="#8FA9C2"/><stop offset=".55" stop-color="#FFFFFF"/><stop offset="1" stop-color="#50677E"/>
      </linearGradient>
      <linearGradient id="ear" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#F6FAFF"/><stop offset=".36" stop-color="#9CB9D5"/><stop offset=".44" stop-color="#17253A"/><stop offset="1" stop-color="#070C16"/>
      </linearGradient>
      <linearGradient id="cap" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#58C5F3"/><stop offset="1" stop-color="#1877AA"/>
      </linearGradient>
      <linearGradient id="hijab" x1="0" y1="0" x2="1" y2="1">
        <stop stop-color="#FFFFFF"/><stop offset=".45" stop-color="#E7F1FB"/><stop offset="1" stop-color="#A5C4DF"/>
      </linearGradient>
      <radialGradient id="iris" cx="38%" cy="35%" r="70%">
        <stop stop-color="#C99755"/><stop offset=".55" stop-color="#6A3B20"/><stop offset="1" stop-color="#1A1413"/>
      </radialGradient>
    </defs>

    <circle cx="128" cy="128" r="124" fill="url(#bg)"/>
    <circle cx="128" cy="128" r="121" fill="none" stroke="#FFFFFF" stroke-opacity=".10" stroke-width="2"/>
    <path d="M35 177c24-13 44-16 63-17 9 7 18 11 30 11s22-4 31-11c21 1 42 4 65 17l18 79H17l18-79Z" fill="url(#coat)"/>
    <path d="M96 160l32 27 32-27-12 96h-40l-12-96Z" fill="url(#scrub)"/>
    <path d="M96 161l32 26-18 23-25-41 11-8ZM160 161l-32 26 18 23 25-41-11-8Z" fill="#FFFFFF" fill-opacity=".92"/>
    <path d="M51 201c13-15 26-22 43-27M205 201c-13-15-26-22-43-27" fill="none" stroke="#7E9DBA" stroke-opacity=".25" stroke-width="4"/>

    $behindHair
    <ellipse cx="128" cy="103" rx="52" ry="61" fill="url(#skin)"/>
    <path d="M82 110c5 31 23 52 47 53 23 0 42-19 49-49-4 38-23 60-50 60-28 0-46-23-46-64Z" fill="url(#skinShadow)" opacity=".42"/>
    <ellipse cx="95" cy="109" rx="13" ry="8" fill="#E6867A" fill-opacity=".16"/>
    <ellipse cx="162" cy="109" rx="13" ry="8" fill="#E6867A" fill-opacity=".14"/>
    <path d="M126 100c-2 10-5 18-3 23 2 4 7 5 11 2" fill="none" stroke="#A75F4A" stroke-opacity=".40" stroke-width="2.5" stroke-linecap="round"/>
    <path d="M116 136c8 7 17 8 25 0" fill="none" stroke="#A94B55" stroke-width="4" stroke-linecap="round"/>
    <path d="M119 140c6 3 12 3 18 0" fill="none" stroke="#FFD2C7" stroke-opacity=".55" stroke-width="1.6" stroke-linecap="round"/>

    $hijabFaceFrame
    $frontHair

    <g>
      <ellipse cx="105" cy="100" rx="14" ry="10" fill="#F9FCFF"/>
      <ellipse cx="151" cy="100" rx="14" ry="10" fill="#F9FCFF"/>
      <circle cx="107" cy="101" r="7.2" fill="url(#iris)"/>
      <circle cx="149" cy="101" r="7.2" fill="url(#iris)"/>
      <circle cx="107" cy="101" r="3.5" fill="#101521"/>
      <circle cx="149" cy="101" r="3.5" fill="#101521"/>
      <circle cx="104.5" cy="98.5" r="2.1" fill="#FFFFFF"/>
      <circle cx="146.5" cy="98.5" r="2.1" fill="#FFFFFF"/>
      <path d="M91 92c8-8 20-9 28-3M137 89c9-6 21-5 28 3" fill="none" stroke="$hairBottom" stroke-width="4.2" stroke-linecap="round"/>
    </g>
    $glasses

    <path d="M77 94C72 52 92 27 127 25c37-2 59 24 55 69" fill="none" stroke="$accent" stroke-opacity=".30" stroke-width="13" stroke-linecap="round"/>
    <path d="M78 93C74 56 92 33 127 31c34-2 55 22 53 62" fill="none" stroke="#121B2A" stroke-width="12" stroke-linecap="round"/>
    <path d="M82 84c1-26 19-45 46-47 25-1 45 17 48 45" fill="none" stroke="url(#metal)" stroke-width="7" stroke-linecap="round"/>

    <g>
      <ellipse cx="78" cy="100" rx="16" ry="25" fill="$accent" fill-opacity=".25"/>
      <ellipse cx="78" cy="100" rx="13" ry="22" fill="url(#ear)"/>
      <ellipse cx="78" cy="100" rx="8" ry="15" fill="#101927"/>
      <path d="M72 84c-5 7-6 22-2 31" fill="none" stroke="#FFFFFF" stroke-opacity=".32" stroke-width="2" stroke-linecap="round"/>
    </g>
    <g>
      <ellipse cx="179" cy="100" rx="17" ry="26" fill="$accent" fill-opacity=".30"/>
      <ellipse cx="179" cy="100" rx="14" ry="23" fill="url(#ear)"/>
      <ellipse cx="179" cy="100" rx="9" ry="16" fill="#101927"/>
      <circle cx="179" cy="100" r="7" fill="#0A2231"/>
      <path d="M175 100h8M179 96v8" stroke="$accent" stroke-width="2.4" stroke-linecap="round"/>
      <path d="M173 84c-5 8-5 23-1 32" fill="none" stroke="#FFFFFF" stroke-opacity=".35" stroke-width="2" stroke-linecap="round"/>
    </g>

    <path d="M183 115c-1 14-8 20-22 22" fill="none" stroke="$accent" stroke-opacity=".28" stroke-width="9" stroke-linecap="round"/>
    <path d="M183 115c-1 14-8 20-22 22" fill="none" stroke="#27394D" stroke-width="5" stroke-linecap="round"/>
    <rect x="155" y="133" width="15" height="7" rx="3.5" fill="url(#metal)" transform="rotate(-8 162 136.5)"/>
    <rect x="157" y="134.5" width="8" height="4" rx="2" fill="$accent" transform="rotate(-8 161 136.5)"/>

    <path d="M97 173c-16 10-17 35-7 49 7 10 20 8 24-3 3-8 1-17-4-24M159 173c15 11 16 29 12 41" fill="none" stroke="#08101B" stroke-width="8" stroke-linecap="round"/>
    <path d="M97 173c-16 10-17 35-7 49M159 173c15 11 16 29 12 41" fill="none" stroke="#536F86" stroke-width="3" stroke-linecap="round"/>
    <circle cx="171" cy="218" r="13" fill="$accent" fill-opacity=".22"/>
    <circle cx="171" cy="218" r="10" fill="url(#metal)"/>
    <circle cx="171" cy="218" r="6" fill="#142131"/>
    <circle cx="169" cy="216" r="2.5" fill="#FFFFFF" fill-opacity=".70"/>

    <path d="M89 75c7-18 19-29 35-33" fill="none" stroke="#FFFFFF" stroke-opacity=".18" stroke-width="4" stroke-linecap="round"/>
    <path d="M92 178c10 9 21 13 35 13" fill="none" stroke="#FFFFFF" stroke-opacity=".28" stroke-width="3" stroke-linecap="round"/>
  </svg>''';
}

final List<ProfileAvatarOption> kProfileAvatarOptions = [
  ProfileAvatarOption(
    key: 'gamer_doctor_m_01',
    label: 'Avatar 1',
    svgMarkup: _avatarSvg(
      hairStyle: _AvatarHairStyle.swept,
      skinTop: '#F7BE94',
      skinBottom: '#C87856',
      hairTop: '#74391F',
      hairBottom: '#2C1715',
      bgStart: '#2169F2',
      bgEnd: '#21E2CD',
    ),
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_f_01',
    label: 'Avatar 2',
    svgMarkup: _avatarSvg(
      hairStyle: _AvatarHairStyle.long,
      skinTop: '#F8BD96',
      skinBottom: '#C87859',
      hairTop: '#7D3F27',
      hairBottom: '#2E1717',
      bgStart: '#1F6DFF',
      bgEnd: '#29E0C6',
      accent: '#55F5EE',
    ),
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_hijab_01',
    label: 'Avatar 3',
    svgMarkup: _avatarSvg(
      hairStyle: _AvatarHairStyle.hijab,
      skinTop: '#EFB286',
      skinBottom: '#B96E4E',
      hairTop: '#4B3028',
      hairBottom: '#241819',
      bgStart: '#2173FF',
      bgEnd: '#24E1C6',
      accent: '#4BF4EB',
    ),
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_f_02',
    label: 'Avatar 4',
    svgMarkup: _avatarSvg(
      hairStyle: _AvatarHairStyle.glassesBob,
      skinTop: '#F5B58C',
      skinBottom: '#C26E50',
      hairTop: '#3D2D35',
      hairBottom: '#15141D',
      bgStart: '#3559DE',
      bgEnd: '#40D5C7',
      accent: '#5AF3EE',
    ),
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_m_02',
    label: 'Avatar 5',
    svgMarkup: _avatarSvg(
      hairStyle: _AvatarHairStyle.surgicalCap,
      skinTop: '#F2B387',
      skinBottom: '#B86F51',
      hairTop: '#3A2824',
      hairBottom: '#17151A',
      bgStart: '#1E66F5',
      bgEnd: '#1DDBC8',
      accent: '#43F1E6',
    ),
  ),
  ProfileAvatarOption(
    key: 'gamer_doctor_m_03',
    label: 'Avatar 6',
    svgMarkup: _avatarSvg(
      hairStyle: _AvatarHairStyle.curls,
      skinTop: '#C9855F',
      skinBottom: '#7C4938',
      hairTop: '#36202A',
      hairBottom: '#15131D',
      bgStart: '#2459D7',
      bgEnd: '#27D8C6',
      accent: '#4AF0E7',
    ),
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
