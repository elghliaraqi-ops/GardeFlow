/// Allow only verified HTTPS pairs from Commons, Openverse or Radiology Assistant.
bool isSupportedExternalMedicalPreview(Uri? preview, Uri? original) {
  if (preview?.scheme != 'https' || original?.scheme != 'https') return false;
  if (preview!.host == 'radiologyassistant.nl' && original!.host == 'radiologyassistant.nl' &&
      preview.userInfo.isEmpty && original.userInfo.isEmpty && !preview.hasPort && !original.hasPort &&
      preview.query.isEmpty && preview.fragment.isEmpty &&
      RegExp(r'^/(assets|img/containers/main)/').hasMatch(preview.path) &&
      RegExp(r'\.(jpg|jpeg|png|webp)$', caseSensitive: false).hasMatch(preview.path) &&
      !RegExp(r'%2e|%2f|%5c', caseSensitive: false).hasMatch(preview.toString())) return true;
  if (preview.host == 'upload.wikimedia.org' &&
      original!.host == 'commons.wikimedia.org')
    return true;
  if (preview.host == 'api.openverse.org' &&
      original!.host == 'openverse.org') {
    final segment = preview.pathSegments;
    final uuid =
        segment.length == 5 &&
            segment[0] == 'v1' &&
            segment[1] == 'images' &&
            segment[3] == 'thumb' &&
            segment[4].isEmpty
        ? segment[2]
        : null;
    if (uuid == null ||
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
          caseSensitive: false,
        ).hasMatch(uuid))
      return false;
    return original.path == '/image/$uuid';
  }
  return false;
}
