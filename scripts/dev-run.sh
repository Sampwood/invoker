#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Invoker.xcodeproj"
SCHEME="${SCHEME:-Invoker}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.build/DerivedData}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$SCHEME.app"
STAMP_FILE="$ROOT_DIR/.build/.dev-run.stamp"

watched_file_changed() {
    if [[ ! -f "$STAMP_FILE" ]]; then
        return 0
    fi

    find "$ROOT_DIR/Invoker" "$PROJECT_PATH" \
        -type f \
        \( -name "*.swift" -o -name "*.plist" -o -name "project.pbxproj" \) \
        -newer "$STAMP_FILE" \
        -print \
        -quit | grep -q .
}

build_and_launch() {
    mkdir -p "$DERIVED_DATA_PATH" "$(dirname "$STAMP_FILE")"

    echo
    echo "Building $SCHEME ($CONFIGURATION)..."
    if xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        build; then
        echo "Relaunching $APP_PATH"
        pkill -x "$SCHEME" >/dev/null 2>&1 || true
        open "$APP_PATH"
    else
        echo "Build failed. Fix the error, save a file, and the watcher will try again."
    fi

    touch "$STAMP_FILE"
}

build_and_launch
echo
echo "Watching Swift and project files. Press Ctrl-C to stop."

while true; do
    sleep 1

    if watched_file_changed; then
        sleep 0.3
        build_and_launch
    fi
done
