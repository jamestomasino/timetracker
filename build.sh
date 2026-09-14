#!/usr/bin/env bash
#
# build.sh — compile the Time Tracker app and its tests using swiftc only
# (no Xcode required). Produces build/TimeTracker.app and runs the test suite.
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="TimeTracker"
BUNDLE_ID="local.timetracker"
MIN_MACOS="14.0"
TARGET="arm64-apple-macosx${MIN_MACOS}"
BUILD="build"
APP_DIR="${BUILD}/${APP_NAME}.app"
BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

CORE_SRC=(
  Sources/Core/TimeEntry.swift
  Sources/Core/CSVExporter.swift
  Sources/Core/TimeTrackerEngine.swift
  Sources/Core/EntryStore.swift
  Sources/Core/TimeFormat.swift
  Sources/Core/AppSettings.swift
  Sources/Core/BreakReminder.swift
  Sources/Core/SettingsStore.swift
  Sources/Core/TrackerViewModel.swift
  Sources/Core/ToastCenter.swift
)
APP_SRC=(
  Sources/App/TimeTrackerApp.swift
  Sources/App/ContentView.swift
  Sources/App/TaskRow.swift
  Sources/App/AppNotifications.swift
  Sources/App/SettingsView.swift
)
TEST_SRC=(
  Tests/main.swift
)

echo "==> Cleaning build dir"
rm -rf "$BUILD"
mkdir -p "$BIN_DIR" "$RES_DIR"

echo "==> Building app (target ${TARGET})"
swiftc \
  -O \
  -parse-as-library \
  -target "$TARGET" \
  -module-name "$APP_NAME" \
  -o "$BIN_DIR/${APP_NAME}" \
  "${CORE_SRC[@]}" "${APP_SRC[@]}"

echo "==> Writing Info.plist"
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Time Tracker</string>
    <key>CFBundleDisplayName</key>     <string>Time Tracker</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>0.1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>LSMinimumSystemVersion</key>  <string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

echo "==> Writing PkgInfo"
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "==> Ad-hoc code signing (required to launch a GUI app)"
codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || \
  echo "    (codesign skipped/failed; app may still run)"

MODE="${1:-build}"

if [ "$MODE" = "test" ]; then
  echo "==> Building + running tests"
  swiftc \
    -target "$TARGET" \
    -module-name "${APP_NAME}Tests" \
    -o "${BUILD}/tests" \
    "${CORE_SRC[@]}" "${TEST_SRC[@]}"
  echo "==> Running test executable"
  "${BUILD}/tests"
  echo
  echo "    Tests: ${BUILD}/tests"
fi

echo
echo "==> Done."
echo "    App:  ${APP_DIR}"
echo "    Run:  open ${APP_DIR}"
echo
echo "Usage:  bash build.sh          # build the app"
echo "        bash build.sh test     # build the app + run the test suite"
