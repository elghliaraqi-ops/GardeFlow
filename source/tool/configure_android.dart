// Exécuter avec `dart tool/configure_android.dart` après flutter create.
// Ne dépend d'aucun package : fonctionne avant flutter pub get.
import 'dart:convert';
import 'dart:io';

const packageName = 'com.huim6.huim6_planning';

String insertOnce(String source, String marker, String anchor, String addition) {
  if (source.contains(marker)) return source;
  if (!source.contains(anchor)) throw StateError('Structure Android non reconnue : $anchor');
  return source.replaceFirst(anchor, '$anchor\n$addition');
}

void configure(Directory root) {
  File file(String path) => File('${root.path}/$path');
  final jsonFile = file('android/app/google-services.json');
  if (!jsonFile.existsSync()) {
    throw StateError('Ajouter google-services.json à la racine puis relancer tool/android.ps1.');
  }
  final config = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
  if (config['project_info']?['project_id'] != 'planninghm6') {
    throw StateError('google-services.json doit provenir du projet Firebase planninghm6.');
  }
  final clients = config['client'] as List<dynamic>? ?? [];
  if (!clients.any((client) => client['client_info']?['android_client_info']?['package_name'] == packageName)) {
    throw StateError('Créer une application Android Firebase avec le package $packageName.');
  }

  final kts = file('android/app/build.gradle.kts').existsSync();
  final app = file(kts ? 'android/app/build.gradle.kts' : 'android/app/build.gradle');
  final settings = file(kts ? 'android/settings.gradle.kts' : 'android/settings.gradle');
  var appText = app.readAsStringSync();
  if (!appText.contains(packageName)) {
    throw StateError('Le package Android existant diffère de $packageName. Ne pas changer un identifiant publié.');
  }
  var settingsText = settings.readAsStringSync();
  // alarm >=5 exige Kotlin >=2.0.0. Les templates Flutter récents sont déjà
  // au-dessus ; ce remplacement ne touche que d'anciens templates Kotlin 1.x.
  settingsText = settingsText.replaceAllMapped(
    RegExp(r'id\("org\.jetbrains\.kotlin\.android"\)\s+version\s+"1\.[^"]+"'),
    (_) => 'id("org.jetbrains.kotlin.android") version "2.0.0"',
  );
  settingsText = settingsText.replaceAllMapped(
    RegExp(r'''id ['"]org\.jetbrains\.kotlin\.android['"] version ['"]1\.[^'"]+['"]'''),
    (_) => 'id "org.jetbrains.kotlin.android" version "2.0.0"',
  );
  settingsText = insertOnce(settingsText, 'com.google.gms.google-services', 'plugins {',
      kts ? '    id("com.google.gms.google-services") version "4.4.4" apply false' : '    id "com.google.gms.google-services" version "4.4.4" apply false');
  appText = insertOnce(appText, 'com.google.gms.google-services', 'plugins {',
      kts ? '    id("com.google.gms.google-services")' : '    id "com.google.gms.google-services"');
  appText = insertOnce(appText, kts ? 'isCoreLibraryDesugaringEnabled' : 'coreLibraryDesugaringEnabled', 'compileOptions {',
      kts ? '        isCoreLibraryDesugaringEnabled = true' : '        coreLibraryDesugaringEnabled true');
  appText = insertOnce(appText, 'multiDexEnabled', 'defaultConfig {',
      kts ? '        multiDexEnabled = true' : '        multiDexEnabled true');
  if (!appText.contains('desugar_jdk_libs')) {
    appText += kts
        ? '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        : "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
  }
  // Workaround recommandé pour les crashs Flutter/Android 12L+ avec le
  // core library desugaring utilisé par les notifications programmées.
  if (!appText.contains('androidx.window:window:1.0.0')) {
    appText += kts
        ? '\ndependencies {\n    implementation("androidx.window:window:1.0.0")\n    implementation("androidx.window:window-java:1.0.0")\n}\n'
        : "\ndependencies {\n    implementation 'androidx.window:window:1.0.0'\n    implementation 'androidx.window:window-java:1.0.0'\n}\n";
  }
  // GardeFlow V11.3.1 : les plugins Android récents (notamment
  // flutter_plugin_android_lifecycle) exigent une compilation contre API 36.
  // targetSdk/minSdk restent indépendants de ce choix.
  appText = appText.replaceAll('compileSdk = flutter.compileSdkVersion', 'compileSdk = 36');
  appText = appText.replaceAll('compileSdkVersion flutter.compileSdkVersion', 'compileSdkVersion 36');
  appText = appText.replaceAll(RegExp(r'compileSdk\s*=\s*3[0-5]'), 'compileSdk = 36');
  appText = appText.replaceAll(RegExp(r'compileSdkVersion\s+3[0-5]'), 'compileSdkVersion 36');

  // Firebase Android exige au moins API 23 ; garder une valeur supérieure du SDK.
  appText = appText.replaceAll('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(23, flutter.minSdkVersion)');
  appText = appText.replaceAll('minSdkVersion flutter.minSdkVersion', 'minSdkVersion Math.max(23, flutter.minSdkVersion)');
  // ML Kit Text Recognition utilise uniquement le script latin dans GardeFlow.
  // Le plugin référence aussi ses modules linguistiques optionnels ; R8 exige
  // qu'ils soient explicitement ignorés lorsqu'ils ne sont pas embarqués.
  final proguardRules = file('android/app/proguard-rules.pro');
  const mlKitOptionalLanguageRules = '''
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
''';
  var proguardText = proguardRules.existsSync()
      ? proguardRules.readAsStringSync()
      : '';
  if (!proguardText.contains('com.google.mlkit.vision.text.chinese')) {
    if (proguardText.isNotEmpty && !proguardText.endsWith('\n')) {
      proguardText += '\n';
    }
    proguardText += mlKitOptionalLanguageRules;
    proguardRules.writeAsStringSync(proguardText);
  }

  if (!appText.contains('proguard-rules.pro')) {
    if (kts) {
      const releaseAnchor = 'release {';
      const releaseByNameAnchor = 'getByName("release") {';
      const ruleLine =
          '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")';
      if (appText.contains(releaseAnchor)) {
        appText = appText.replaceFirst(
          releaseAnchor,
          '$releaseAnchor\n$ruleLine',
        );
      } else if (appText.contains(releaseByNameAnchor)) {
        appText = appText.replaceFirst(
          releaseByNameAnchor,
          '$releaseByNameAnchor\n$ruleLine',
        );
      } else {
        throw StateError('Bloc release Android Kotlin introuvable.');
      }
    } else {
      const releaseAnchor = 'release {';
      const ruleLine =
          "            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'";
      if (!appText.contains(releaseAnchor)) {
        throw StateError('Bloc release Android Groovy introuvable.');
      }
      appText = appText.replaceFirst(
        releaseAnchor,
        '$releaseAnchor\n$ruleLine',
      );
    }
  }


  final manifest = file('android/app/src/main/AndroidManifest.xml');
  var xml = manifest.readAsStringSync();
  for (final permission in ['INTERNET', 'POST_NOTIFICATIONS', 'RECEIVE_BOOT_COMPLETED', 'SCHEDULE_EXACT_ALARM', 'VIBRATE', 'WAKE_LOCK', 'USE_FULL_SCREEN_INTENT', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK', 'ACCESS_NOTIFICATION_POLICY']) {
    final name = 'android.permission.$permission';
    if (!xml.contains(name)) {
      final opening = RegExp(r'<manifest\b[^>]*>').firstMatch(xml);
      if (opening == null) throw StateError('Manifest Android invalide');
      xml = xml.replaceRange(opening.end, opening.end, '\n    <uses-permission android:name="$name" />');
    }
  }
  final appOpening = RegExp(r'<application\b[^>]*>').firstMatch(xml);
  if (appOpening == null) throw StateError('Application absente du manifest');
  var additions = '';
  if (!xml.contains('com.google.firebase.messaging.default_notification_channel_id')) {
    additions += '\n        <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="huim6_push" />';
  }
  if (!xml.contains('com.google.firebase.messaging.default_notification_icon')) {
    additions += '\n        <meta-data android:name="com.google.firebase.messaging.default_notification_icon" android:resource="@drawable/ic_stat_huim6" />';
  }
  if (!xml.contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver')) {
    additions += '\n        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />';
  }
  if (!xml.contains('com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver')) {
    additions += '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>''';
  }
  xml = xml.replaceRange(appOpening.end, appOpening.end, additions);
  xml = xml.replaceFirst('android:label="huim6_planning"', 'android:label="GardeFlow"');
  xml = xml.replaceFirst('android:label="HUIM6 Planning"', 'android:label="GardeFlow"');

  settings.writeAsStringSync(settingsText);
  app.writeAsStringSync(appText);
  manifest.writeAsStringSync(xml);
  final resources = Directory('${root.path}/tool/android-res');
  for (final source in resources.listSync(recursive: true).whereType<File>()) {
    final relative = source.path.substring(resources.path.length + 1);
    final target = file('android/app/src/main/res/$relative');
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
  }
  stdout.writeln('Android configuré : $packageName (Firebase planninghm6).');
}

void main(List<String> args) {
  try {
    configure(Directory(args.isEmpty ? '.' : args.first));
  } catch (e) {
    stderr.writeln('Configuration interrompue : $e');
    exitCode = 1;
  }
}
