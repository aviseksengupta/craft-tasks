#!/bin/zsh
# Build "Craft Tasks.app" from the Swift package.
set -e
cd "$(dirname "$0")"
swift build -c release

APP="Craft Tasks.app"
ICON_SRC="Resources/bw-logo-1.png"
ICONSET="Resources/AppIcon.iconset"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CraftTasks "$APP/Contents/MacOS/CraftTasks"

# Build the .icns from the source logo (regenerated every build so the
# icon always tracks Resources/bw-logo-1.png).
if [ -f "$ICON_SRC" ]; then
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "Warning: $ICON_SRC not found, app will use the default icon"
fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>CraftTasks</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.avisek.crafttasks</string>
    <key>CFBundleName</key><string>Craft Tasks</string>
    <key>CFBundleDisplayName</key><string>Craft Tasks</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"
