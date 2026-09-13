#!/usr/bin/env bash
# ============================================================
# prepare_windows.sh — تهيئة مجلد windows/ المولَّد من قالب Flutter
# في CI (نفس نهج prepare_android.sh — مجلدات المنصات لا تُودَع).
# يُنفَّذ بعد «flutter create --platforms=windows» وقبل «flutter build windows»:
#   1) BINARY_NAME=PharmacyOS  → PharmacyOS.exe
#   2) نافذة 1280×820 بعنوان Pharmacy OS (قبل أن يتولى window_manager)
#   3) أيقونة العلامة من brand/desktop/app_icon.ico
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."   # mobile/

echo "== prepare_windows: BINARY_NAME = PharmacyOS =="
sed -i 's/set(BINARY_NAME "mobile")/set(BINARY_NAME "PharmacyOS")/' windows/CMakeLists.txt
grep -q 'set(BINARY_NAME "PharmacyOS")' windows/CMakeLists.txt

echo "== prepare_windows: window title/size =="
sed -i 's/Win32Window::Size size(1280, 720);/Win32Window::Size size(1280, 820);/' windows/runner/main.cpp
sed -i 's/window.Create(L"mobile", origin, size)/window.Create(L"Pharmacy OS", origin, size)/' windows/runner/main.cpp
grep -q 'L"Pharmacy OS"' windows/runner/main.cpp
grep -q 'size(1280, 820)' windows/runner/main.cpp

echo "== prepare_windows: brand app icon =="
cp brand/desktop/app_icon.ico windows/runner/resources/app_icon.ico

echo "== prepare_windows: OK =="
