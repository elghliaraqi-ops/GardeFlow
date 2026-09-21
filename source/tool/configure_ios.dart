// Configure GardeFlow after `flutter create --platforms=ios`.
// Pure Dart: runs with the Dart bundled inside Flutter, before CocoaPods.
import 'dart:io';

const bundleId = 'com.huim6.gardeflow';
const deploymentTarget = '13.0';

String ensurePlistString(String source, String key, String value) {
  final pattern = RegExp('<key>${RegExp.escape(key)}</key>\\s*<string>[^<]*</string>');
  final replacement = '<key>$key</key>\n\t<string>$value</string>';
  if (pattern.hasMatch(source)) return source.replaceFirst(pattern, replacement);
  return source.replaceFirst('</dict>', '\t$replacement\n</dict>');
}

String ensureBackgroundModes(String source) {
  if (source.contains('<key>UIBackgroundModes</key>')) return source;
  const block = '''
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>fetch</string>
\t\t<string>remote-notification</string>
\t</array>
''';
  return source.replaceFirst('</dict>', '$block</dict>');
}

void copyDirectory(Directory source, Directory target) {
  if (!source.existsSync()) return;
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);
  for (final entity in source.listSync(recursive: true)) {
    final relative = entity.path.substring(source.path.length + 1);
    final destination = '${target.path}/$relative';
    if (entity is Directory) {
      Directory(destination).createSync(recursive: true);
    } else if (entity is File) {
      File(destination).parent.createSync(recursive: true);
      entity.copySync(destination);
    }
  }
}

String addResourceToPbx(String pbx, String fileName, String fileType, String buildId, String fileId) {
  if (pbx.contains('/* $fileName */')) return pbx;

  final buildMarker = '/* Begin PBXBuildFile section */';
  final refMarker = '/* Begin PBXFileReference section */';
  if (!pbx.contains(buildMarker) || !pbx.contains(refMarker)) {
    throw StateError('Structure Xcode non reconnue (sections PBX absentes).');
  }
  pbx = pbx.replaceFirst(
    buildMarker,
    '$buildMarker\n\t\t$buildId /* $fileName in Resources */ = {isa = PBXBuildFile; fileRef = $fileId /* $fileName */; };',
  );
  pbx = pbx.replaceFirst(
    refMarker,
    '$refMarker\n\t\t$fileId /* $fileName */ = {isa = PBXFileReference; lastKnownFileType = $fileType; path = "$fileName"; sourceTree = "<group>"; };',
  );

  final runnerGroup = RegExp(
    r'(\/\* Runner \*\/ = \{\s*isa = PBXGroup;\s*children = \()'
  );
  if (!runnerGroup.hasMatch(pbx)) {
    throw StateError('Groupe Runner introuvable dans project.pbxproj.');
  }
  pbx = pbx.replaceFirstMapped(runnerGroup, (m) => '${m.group(1)}\n\t\t\t\t$fileId /* $fileName */,');

  final runnerTarget = RegExp(
    r'\/\* Runner \*\/ = \{\s*isa = PBXNativeTarget;[\s\S]*?buildPhases = \(([\s\S]*?)\);'
  ).firstMatch(pbx);
  if (runnerTarget == null) {
    throw StateError('Target Runner introuvable dans project.pbxproj.');
  }
  final resourceRef = RegExp(r'([A-F0-9]{24}) \/\* Resources \*\/').firstMatch(runnerTarget.group(1)!);
  if (resourceRef == null) {
    throw StateError('Référence Resources du target Runner introuvable.');
  }
  final resourceId = resourceRef.group(1)!;
  final resources = RegExp(
    '(${RegExp.escape(resourceId)}' + r' \/\* Resources \*\/ = \{\s*isa = PBXResourcesBuildPhase;[\s\S]*?files = \()'
  );
  if (!resources.hasMatch(pbx)) {
    throw StateError('Phase Resources de Runner introuvable dans project.pbxproj.');
  }
  pbx = pbx.replaceFirstMapped(resources, (m) => '${m.group(1)}\n\t\t\t\t$buildId /* $fileName in Resources */,');
  return pbx;
}

void configure(Directory root) {
  File file(String path) => File('${root.path}/$path');
  final pbxFile = file('ios/Runner.xcodeproj/project.pbxproj');
  final infoFile = file('ios/Runner/Info.plist');
  if (!pbxFile.existsSync() || !infoFile.existsSync()) {
    throw StateError('Projet iOS absent. Lancer d’abord tool/ios.sh.');
  }

  var pbx = pbxFile.readAsStringSync();
  // Keep test target identifiers distinct while assigning the production bundle id.
  pbx = pbx.replaceAllMapped(
    RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);'),
    (m) {
      final current = m.group(1)!.trim();
      final suffix = current.contains('RunnerTests') ? '.RunnerTests' : '';
      return 'PRODUCT_BUNDLE_IDENTIFIER = $bundleId$suffix;';
    },
  );
  pbx = pbx.replaceAllMapped(
    RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = [^;]+;'),
    (_) => 'IPHONEOS_DEPLOYMENT_TARGET = $deploymentTarget;',
  );

  var info = infoFile.readAsStringSync();
  info = ensurePlistString(info, 'CFBundleDisplayName', 'GardeFlow');
  info = ensurePlistString(info, 'CFBundleName', 'GardeFlow');
  info = ensurePlistString(
    info,
    'NSCameraUsageDescription',
    'GardeFlow utilise l’appareil photo uniquement pour publier une photo d’astreinte lorsque vous êtes administrateur.',
  );
  info = ensurePlistString(
    info,
    'NSPhotoLibraryUsageDescription',
    'GardeFlow accède à votre photothèque uniquement pour sélectionner une photo d’astreinte à publier.',
  );
  info = ensurePlistString(
    info,
    'NSPhotoLibraryAddUsageDescription',
    'GardeFlow peut enregistrer un document ou une image que vous choisissez explicitement.',
  );
  info = ensureBackgroundModes(info);
  infoFile.writeAsStringSync(info);

  final iosRes = Directory('${root.path}/tool/ios-res');
  copyDirectory(
    Directory('${iosRes.path}/AppIcon.appiconset'),
    Directory('${root.path}/ios/Runner/Assets.xcassets/AppIcon.appiconset'),
  );
  copyDirectory(
    Directory('${iosRes.path}/LaunchImage.imageset'),
    Directory('${root.path}/ios/Runner/Assets.xcassets/LaunchImage.imageset'),
  );

  // Firebase configuration is optional for compilation but required for FCM on iPhone.
  final rootFirebase = file('GoogleService-Info.plist');
  final runnerFirebase = file('ios/Runner/GoogleService-Info.plist');
  if (rootFirebase.existsSync()) {
    rootFirebase.copySync(runnerFirebase.path);
    pbx = addResourceToPbx(
      pbx,
      'GoogleService-Info.plist',
      'text.plist.xml',
      'A1B2C3D4E5F60718293A4B5C',
      'A1B2C3D4E5F60718293A4B5D',
    );
  }

  // Privacy manifest for the app-owned UserDefaults usage (SharedPreferences).
  final privacy = file('ios/Runner/PrivacyInfo.xcprivacy');
  privacy.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyTrackingDomains</key>
  <array/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array>
    <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
        <string>CA92.1</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
''');
  pbx = addResourceToPbx(
    pbx,
    'PrivacyInfo.xcprivacy',
    'text.xml',
    'B1C2D3E4F5061728394A5B6C',
    'B1C2D3E4F5061728394A5B6D',
  );

  pbxFile.writeAsStringSync(pbx);

  final podfile = file('ios/Podfile');
  if (podfile.existsSync()) {
    var pods = podfile.readAsStringSync();
    if (RegExp(r'^#?\s*platform :ios,', multiLine: true).hasMatch(pods)) {
      pods = pods.replaceFirst(
        RegExp(r'''^#?\s*platform :ios,\s*['"][^'"]+['"]''', multiLine: true),
        "platform :ios, '$deploymentTarget'",
      );
    } else {
      pods = "platform :ios, '$deploymentTarget'\n$pods";
    }
    podfile.writeAsStringSync(pods);
  }

  stdout.writeln('iOS configuré : GardeFlow / $bundleId / iOS $deploymentTarget+.');
  if (!rootFirebase.existsSync()) {
    stdout.writeln('NOTE : GoogleService-Info.plist absent. L’app compile, mais les push Firebase iOS resteront désactivés jusqu’à son ajout.');
  }
}

void main(List<String> args) {
  try {
    configure(Directory(args.isEmpty ? '.' : args.first));
  } catch (e, st) {
    stderr.writeln('Configuration iOS interrompue : $e');
    stderr.writeln(st);
    exitCode = 1;
  }
}
