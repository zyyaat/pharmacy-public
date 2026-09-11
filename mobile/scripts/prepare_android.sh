#!/usr/bin/env bash
# Task 59 — يرقّع مجلد android/ المولود حديثًا بأمر flutter create داخل CI.
# مجلد المنصة لا يُودع في المستودع إطلاقًا (.gitignore)؛ تُولّده نسخة Flutter
# المثبتة في الـ workflow ثم يطبق هذا السكربت تخصيصاتنا الثلاثة الثابتة:
#   1) إذن INTERNET (قالب main لا يتضمنه — موجود فقط في debug/profile)
#   2) اسم التطبيق الظاهر على الجهاز: Pharmacy OS
#   3) minSdk 23 (شرط flutter_secure_storage مع EncryptedSharedPreferences)
set -euo pipefail
cd "$(dirname "$0")/.."

MANIFEST="android/app/src/main/AndroidManifest.xml"
GRADLE="android/app/build.gradle"

[ -f "$MANIFEST" ] || { echo "FATAL: $MANIFEST missing — flutter create must run first" >&2; exit 1; }
[ -f "$GRADLE" ]   || { echo "FATAL: $GRADLE missing" >&2; exit 1; }

# 1) إذن الإنترنت
if ! grep -q "android.permission.INTERNET" "$MANIFEST"; then
  sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\n    <application|' "$MANIFEST"
  echo "OK: INTERNET permission added"
fi

# 2) اسم التطبيق
sed -i 's|android:label="pharmacy_mobile"|android:label="Pharmacy OS"|' "$MANIFEST"
grep -q 'android:label="Pharmacy OS"' "$MANIFEST" || echo "WARN: label pattern not found (template changed?)"

# 3) minSdk 23 — القالب تغيّر أسلوبه عبر النسخ، نغطي النمطين
if grep -q 'minSdk = flutter.minSdkVersion' "$GRADLE"; then
  sed -i 's|minSdk = flutter.minSdkVersion|minSdk = 23|' "$GRADLE"
elif grep -q 'minSdkVersion flutter.minSdkVersion' "$GRADLE"; then
  sed -i 's|minSdkVersion flutter.minSdkVersion|minSdkVersion 23|' "$GRADLE"
fi
grep -Eq 'minSdk(Version)? ?= ?23|minSdkVersion 23' "$GRADLE" \
  || { echo "FATAL: minSdk patch did not apply — inspect $GRADLE" >&2; exit 1; }

echo "OK: android/ prepared (INTERNET + label + minSdk 23)"
