#!/bin/bash
set -e

APP_NAME="NotesToMarkdown"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="build"

echo "Building ${APP_NAME}..."

# Compile
mkdir -p "${BUILD_DIR}"
swiftc main.swift \
    -o "${BUILD_DIR}/${APP_NAME}" \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos13.0 \
    -O

# Create .app bundle
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

# Sign ad-hoc so macOS treats it as a proper app (required for Import from iPhone)
codesign --force --deep --sign - "${APP_BUNDLE}"

echo ""
echo "Done! Run with:"
echo "  open ${APP_BUNDLE}"
echo ""
echo "Or with your API key:"
echo "  ANTHROPIC_API_KEY=sk-ant-... open ${APP_BUNDLE}"
echo ""
echo "You can also set the key in-app via the ⚙ button."
