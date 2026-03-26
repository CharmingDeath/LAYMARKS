#!/usr/bin/env bash
set -euo pipefail

echo "== LAYMARKS release preflight =="

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERROR: Flutter is not installed or not on PATH."
  exit 1
fi

if [[ -z "${ANDROID_HOME:-}" ]] && [[ -z "${ANDROID_SDK_ROOT:-}" ]]; then
  echo "ERROR: ANDROID_HOME/ANDROID_SDK_ROOT is not set."
  echo "Set Android SDK path before building Android release artifacts."
  exit 1
fi

if [[ ! -f "android/key.properties" ]]; then
  echo "ERROR: android/key.properties is missing."
  echo "Copy android/key.properties.example -> android/key.properties and fill values."
  exit 1
fi

echo "Running flutter analyze..."
flutter analyze

echo "Running flutter test..."
flutter test

echo "Preflight passed."
