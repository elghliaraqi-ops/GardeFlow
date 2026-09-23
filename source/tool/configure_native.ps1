# Exécuter depuis la racine du projet APRES `flutter create .`
$ErrorActionPreference = 'Stop'

$manifest = 'android/app/src/main/AndroidManifest.xml'
if (Test-Path $manifest) {
  $xml = Get-Content $manifest -Raw
  if ($xml -notmatch 'android.permission.CAMERA') {
    $xml = $xml -replace '<manifest xmlns:android="http://schemas.android.com/apk/res/android">', "<manifest xmlns:android=`"http://schemas.android.com/apk/res/android`">`r`n    <uses-permission android:name=`"android.permission.CAMERA`" />`r`n    <uses-permission android:name=`"android.permission.POST_NOTIFICATIONS`" />"
    Set-Content -Path $manifest -Value $xml -Encoding utf8
    Write-Host 'Permissions Android ajoutees.' -ForegroundColor Green
  }
}

$plist = 'ios/Runner/Info.plist'
if (Test-Path $plist) {
  $txt = Get-Content $plist -Raw
  if ($txt -notmatch 'NSCameraUsageDescription') {
    $insert = @"
	<key>NSCameraUsageDescription</key>
	<string>HUIM6 utilise la caméra pour photographier les tableaux de garde et d'astreinte.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>HUIM6 utilise la photothèque pour ajouter un tableau de garde ou d'astreinte.</string>
"@
    $txt = $txt -replace '</dict>', "$insert`r`n</dict>"
    Set-Content -Path $plist -Value $txt -Encoding utf8
    Write-Host 'Descriptions iOS ajoutees.' -ForegroundColor Green
  }
}
Write-Host 'Configuration native terminee.' -ForegroundColor Cyan
