#!/usr/bin/env bash
set -euo pipefail
# Executed as a SINGLE bash process by reactivecircus/android-emulator-runner.
# Its script: field otherwise runs each line separately under sh -c.
mkdir -p android-startup-report
capture() {
  adb exec-out screencap -p > android-startup-report/screen.png 2>/dev/null || true
  adb logcat -d -v threadtime > android-startup-report/logcat.txt 2>/dev/null || true
  adb shell dumpsys activity activities > android-startup-report/activity.txt 2>/dev/null || true
  adb shell uiautomator dump /sdcard/gardeflow-ui.xml >/dev/null 2>&1 || true
  adb shell cat /sdcard/gardeflow-ui.xml > android-startup-report/accessibility.xml 2>/dev/null || true
}
trap capture EXIT
adb logcat -c
adb install -r source/build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.huim6.huim6_planning/.MainActivity
success=0
for i in $(seq 1 24); do
  sleep 5
  adb shell uiautomator dump /sdcard/gardeflow-ui.xml >/dev/null 2>&1 || true
  adb shell cat /sdcard/gardeflow-ui.xml > /tmp/gardeflow-screen.xml 2>/dev/null || true
  if grep -Eq 'Se connecter|Connexion|Numéro de téléphone|Mot de passe' /tmp/gardeflow-screen.xml 2>/dev/null; then
    success=1
    break
  fi
done
capture
if [ "$success" != "1" ]; then
  echo "Release APK did not reach the GardeFlow login screen."
  head -c 10000 /tmp/gardeflow-screen.xml 2>/dev/null || true
  grep -E 'AndroidRuntime|FATAL EXCEPTION|GF_STARTUP|flutter|Flutter|E/.*' android-startup-report/logcat.txt | tail -n 180 || true
  exit 1
fi
echo "PASS: real Android release APK displayed the login UI."
