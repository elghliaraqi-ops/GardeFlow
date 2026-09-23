param(
  [ValidateSet('Prepare', 'Run', 'Apk', 'DebugApk')][string]$Action = 'Prepare',
  [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Invoke-Flutter {
  param([Parameter(ValueFromRemainingArguments=$true)][string[]]$FlutterArgs)
  & flutter @FlutterArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter a echoue (code $LASTEXITCODE)."
  }
}

function Stop-GradleDaemons {
  if (Test-Path 'android/gradlew.bat') {
    Push-Location android
    try {
      & .\gradlew.bat --stop | Out-Host
    } catch {
      Write-Host 'Impossible d arreter Gradle, poursuite du nettoyage...' -ForegroundColor Yellow
    } finally {
      Pop-Location
    }
  }
}

function Clear-AndroidResourceCaches {
  Write-Host 'Reparation du cache Android/Gradle des ressources...' -ForegroundColor Yellow
  Stop-GradleDaemons

  foreach ($path in @('build', '.dart_tool', 'android/.gradle')) {
    if (Test-Path $path) {
      Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  $gradleCaches = Join-Path $env:USERPROFILE '.gradle\caches'
  if (Test-Path $gradleCaches) {
    # Les AAR de Google Play Services sont extraits dans ces caches. Un cache
    # de transformation incomplet peut provoquer des erreurs AAPT indiquant
    # simultanement que les ressources de l app et google_play_services_version
    # sont introuvables.
    Get-ChildItem $gradleCaches -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $transforms = Join-Path $_.FullName 'transforms'
      if (Test-Path $transforms) {
        Remove-Item $transforms -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    Get-ChildItem $gradleCaches -Directory -Filter 'transforms-*' -ErrorAction SilentlyContinue | ForEach-Object {
      Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Assert-AndroidResources {
  $required = @(
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png',
    'android/app/src/main/res/drawable/ic_stat_huim6.xml',
    'android/app/src/main/res/values/styles.xml',
    'android/app/src/main/res/values-night/styles.xml',
    'android/app/src/main/res/drawable/launch_background.xml'
  )
  $missing = @($required | Where-Object { -not (Test-Path $_) })
  if ($missing.Count -gt 0) {
    throw ("Ressources Android manquantes apres configuration :`n - " + ($missing -join "`n - "))
  }
  Write-Host 'Ressources Android verifiees.' -ForegroundColor Green
}

function Invoke-ApkBuildWithRepair {
  param([switch]$Debug)
  $mode = if ($Debug) { '--debug' } else { '--release' }

  & flutter build apk $mode
  if ($LASTEXITCODE -eq 0) { return }

  Write-Host ''
  Write-Host 'Premier build Android en echec. Nettoyage approfondi des caches puis nouvel essai unique...' -ForegroundColor Yellow
  Clear-AndroidResourceCaches
  Invoke-Flutter clean
  Invoke-Flutter pub get
  Assert-AndroidResources

  & flutter build apk $mode
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter a echoue apres reparation du cache (code $LASTEXITCODE)."
  }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter est introuvable. Ajouter flutter\bin au PATH puis rouvrir PowerShell.'
}

# L archive garde un shell Android minimal. Si le projet Android complet n est
# pas present, on le regenere avec le Flutter installe sur le PC.
$manifest = 'android/app/src/main/AndroidManifest.xml'
$gradlew = 'android/gradlew'
$mainKt = 'android/app/src/main/kotlin/com/huim6/huim6_planning/MainActivity.kt'
$mainJava = 'android/app/src/main/java/com/huim6/huim6_planning/MainActivity.java'
$androidComplete = (Test-Path $gradlew) -and (Test-Path $manifest) -and ((Test-Path $mainKt) -or (Test-Path $mainJava))

if (-not $androidComplete) {
  Write-Host 'Regeneration du projet Android moderne (embedding v2)...' -ForegroundColor Cyan
  if (Test-Path 'android') {
    Remove-Item 'android' -Recurse -Force
  }
  Invoke-Flutter create --no-pub --platforms=android --org com.huim6 --project-name huim6_planning .
}

if (-not (Test-Path 'google-services.json')) {
  throw 'google-services.json manque a la racine du projet.'
}
Copy-Item 'google-services.json' 'android/app/google-services.json' -Force

& dart tool/configure_android.dart
if ($LASTEXITCODE -ne 0) {
  throw 'Configuration Android incomplete.'
}

# configure_android.dart restaure aussi toutes les ressources personnalisees,
# y compris ic_launcher, ic_stat_huim6, LaunchTheme et NormalTheme.
Assert-AndroidResources

Write-Host 'Nettoyage des anciens caches Flutter/Gradle du projet...' -ForegroundColor Cyan
if (Test-Path 'android/.gradle') {
  Remove-Item 'android/.gradle' -Recurse -Force -ErrorAction SilentlyContinue
}
Invoke-Flutter clean
Invoke-Flutter pub get
Assert-AndroidResources

$activityPath = if (Test-Path $mainKt) { $mainKt } else { $mainJava }
if (-not (Test-Path $activityPath)) {
  throw 'MainActivity Android introuvable apres regeneration.'
}
$activityText = Get-Content $activityPath -Raw
if ($activityText -notmatch 'io\.flutter\.embedding\.android\.FlutterActivity') {
  throw 'MainActivity n utilise pas Android embedding v2.'
}

if ($Action -eq 'Run') {
  if (-not $Device) {
    Invoke-Flutter devices
    throw 'Relancer avec -Action Run -Device IDENTIFIANT_ANDROID.'
  }
  Invoke-Flutter run -d $Device
}
elseif ($Action -eq 'DebugApk') {
  Invoke-ApkBuildWithRepair -Debug
  Write-Host 'APK debug : build\app\outputs\flutter-apk\app-debug.apk' -ForegroundColor Green
}
elseif ($Action -eq 'Apk') {
  Invoke-ApkBuildWithRepair
  Write-Host 'APK release : build\app\outputs\flutter-apk\app-release.apk' -ForegroundColor Green
}
else {
  Write-Host 'Preparation Android terminee. Lancer -Action Apk pour compiler la release.' -ForegroundColor Green
}
