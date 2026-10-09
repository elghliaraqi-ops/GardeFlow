/// Allow only verified HTTPS pairs from Commons or Openverse.
bool isSupportedExternalMedicalPreview(Uri? preview, Uri? original) {
  if (preview?.scheme != 'https' || original?.scheme != 'https') return false;
  if (preview!.host == 'upload.wikimedia.org' &&
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
