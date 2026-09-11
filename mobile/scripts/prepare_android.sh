#!/usr/bin/env bash
# Task 59 — يرقّع مجلد android/ المولود حديثًا بأمر flutter create داخل CI.
# مجلد المنصة لا يُودع في المستودع إطلاقًا (.gitignore)؛ تُولّده نسخة Flutter
# المثبتة في الـ workflow ثم يطبق هذا السكربت تخصيصاتنا الخمسة الثابتة:
#   1) إذن INTERNET (قالب main لا يتضمنه — موجود فقط في debug/profile)
#   2) اسم التطبيق الظاهر على الجهاز: Pharmacy OS
#   3) minSdk 23 (شرط flutter_secure_storage مع EncryptedSharedPreferences)
#   4) useLegacyPackaging (تثبيت ناجح دائمًا حتى على أجهزة صفحات 16KB الحديثة)
#   5) التوقيع الثابت من key.properties (إن وُجد) — التحديث فوق النسخة المثبتة يعمل
#   6) أيقونة التطبيق = الأيقونة الرسمية للبراند (نفسها المعتمدة في تطبيقات الويب)
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

# 4) تغليف المكتبات الأصلية بوضع الاستخراج (useLegacyPackaging):
#    أحدث الأجهزة (صفحات ذاكرة 16KB) ترفض APK تحتوي مكتبات غير محاذاة 16KB،
#    وهذا الخيار يجعل المكتبات مضغوطة تُستخرج عند التثبيت فينجح التثبيت دائمًا.
#    ترقيع بأمان: إن تغيّر القالب نكتفِ بتحذير ولا نُفشل البناء.
if grep -q "useLegacyPackaging" "$GRADLE"; then
  echo "OK: useLegacyPackaging already present"
else
  sed -i '0,/^    buildTypes {/s//    packagingOptions {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n\n    buildTypes {/' "$GRADLE" || true
  if grep -q "useLegacyPackaging" "$GRADLE"; then
    echo "OK: useLegacyPackaging=true (install-safe on 16KB-page devices)"
  else
    echo "WARN: packagingOptions not inserted (template changed?) — build continues"
  fi
fi

# 5) التوقيع الثابت — أساس «التحديث فوق النسخة المثبتة بلا حذف»:
#    أندرويد يرفض تحديثًا موقعًا بمفتاح مختلف عن المثبت حاليًا، وكانت كل
#    بناءات CI تُوقّع بمفتاح debug مؤقت يتغير كل تشغيل. حين يوجد
#    android/key.properties (من الـ Secrets) نربطه ببكج release ثابتًا.
#    بلا مفتاح: تحذير فقط ويستمر البناء بتوقيع debug كما كان.
if [ -f android/key.properties ]; then
  if grep -q "signingConfigs.release" "$GRADLE"; then
    echo "OK: fixed signing already wired"
  else
    # 5-أ) تحميل خصائص المفتاح قبل android {
    sed -i '0,/^android {/s//def keystoreProperties = new Properties()\ndef keystorePropertiesFile = rootProject.file(\"key.properties\")\nif (keystorePropertiesFile.exists()) {\n    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n}\n\nandroid {/' "$GRADLE" || true
    # 5-ب) كتلة signingConfigs.release قبل buildTypes
    sed -i '0,/^    buildTypes {/s//    signingConfigs {\n        release {\n            keyAlias keystoreProperties[\"keyAlias\"]\n            keyPassword keystoreProperties[\"keyPassword\"]\n            storeFile file(keystoreProperties[\"storeFile\"])\n            storePassword keystoreProperties[\"storePassword\"]\n        }\n    }\n\n    buildTypes {/' "$GRADLE" || true
    # 5-ج) release يستخدم التوقيع الثابت بدل debug
    sed -i 's|signingConfig = signingConfigs.debug|signingConfig = signingConfigs.release|' "$GRADLE" || true
    if grep -q "signingConfig = signingConfigs.release" "$GRADLE" && grep -q "keystoreProperties" "$GRADLE"; then
      echo "OK: release signed with the fixed keystore (updates over installed app work)"
    else
      echo "WARN: signing patch did not apply (template changed?) — falls back to debug signing"
    fi
  fi
else
  echo "WARN: android/key.properties missing — release will use debug signing (update-over-install rejected)"
fi

# 6) أيقونة التطبيق — الأيقونة الرسمية للبراند (نفسها المعتمدة في تطبيقات الواجهة
#    الأمامية: public/brand/pharmacy-os-icon.svg). الملفات الجاهزة في
#    mobile/brand/launcher/ (مولّدة عبر mobile/scripts/gen_launcher_icons.py):
#    ic_launcher بكل الكثافات + النسخة الدائرية + الأيقونة التكيفية adaptive
#    (أعمدة البراند على خلفية #00d084) + أيقونة متجر Play ‏512.
ICON_SRC="brand/launcher"
RES="android/app/src/main/res"
if [ -d "$ICON_SRC" ]; then
  for d in mipmap-mdpi mipmap-hdpi mipmap-xhdpi mipmap-xxhdpi mipmap-xxxhdpi mipmap-anydpi-v26 values; do
    if [ -d "$ICON_SRC/$d" ]; then
      mkdir -p "$RES/$d"
      cp -f "$ICON_SRC/$d/"* "$RES/$d/" 2>/dev/null || true
    fi
  done
  if [ -f "$RES/mipmap-anydpi-v26/ic_launcher.xml" ] && [ -f "$RES/mipmap-xxxhdpi/ic_launcher.png" ] \
      && [ -f "$RES/mipmap-xxxhdpi/ic_launcher_foreground.png" ]; then
    echo "OK: brand launcher icons applied (legacy + round + adaptive v26)"
  else
    echo "WARN: launcher icons copy incomplete — default template icon remains"
  fi
  # خاصية الأيقونة الدائرية في المانيفست (لونشرات الدوائر)
  if ! grep -q "android:roundIcon" "$MANIFEST"; then
    sed -i 's|android:icon="@mipmap/ic_launcher"|android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"|' "$MANIFEST" || true
  fi
  if grep -q "android:roundIcon" "$MANIFEST"; then
    echo "OK: manifest roundIcon wired"
  else
    echo "WARN: roundIcon attribute not added (template changed?)"
  fi
else
  echo "WARN: $ICON_SRC missing — default Flutter launcher icon remains"
fi

echo "OK: android/ prepared (INTERNET + label + minSdk 23 + install-safe packaging + fixed signing + brand icon)"
