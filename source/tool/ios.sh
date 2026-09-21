#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-Prepare}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La compilation iPhone exige macOS + Xcode. Ce script doit être lancé sur un Mac." >&2
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter est introuvable. Installez Flutter puis relancez ce script." >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode est introuvable. Installez Xcode depuis l’App Store." >&2
  exit 1
fi

if [[ ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  echo "Création du projet iOS moderne..."
  rm -rf ios
  flutter create --no-pub --platforms=ios --org com.huim6 --project-name huim6_planning .
fi

dart tool/configure_ios.dart
flutter clean
flutter pub get

if command -v pod >/dev/null 2>&1; then
  (cd ios && pod install --repo-update)
else
  echo "CocoaPods n’est pas installé. Flutter/Xcode pourra vous le demander avant l’archive." >&2
fi

case "$ACTION" in
  Prepare|prepare)
    echo "Préparation iOS terminée."
    ;;
  Unsigned|unsigned)
    flutter build ios --release --no-codesign
    echo "Build iOS non signé : build/ios/iphoneos/Runner.app"
    ;;
  Ipa|ipa|IPA)
    flutter build ipa --release
    echo "IPA : build/ios/ipa/"
    ;;
  *)
    echo "Usage: ./tool/ios.sh [Prepare|Unsigned|Ipa]" >&2
    exit 2
    ;;
esac
