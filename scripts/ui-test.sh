#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$ROOT_DIR/.build/UITests"
mkdir -p "$TEST_ROOT/Runs"
RUN_DIR="$(mktemp -d "$TEST_ROOT/Runs/$(date +%Y%m%d-%H%M%S)-XXXXXX")"
# The sandboxed runner must not read receipts from the protected Documents folder.
RUNTIME_DIR="$(mktemp -d /private/tmp/invoker-ui-tests-XXXXXX)"

printf 'UI test evidence: %s\n' "$RUN_DIR"
printf '%s\n' "$RUNTIME_DIR" > "$RUN_DIR/runtime-directory.txt"
mkdir -p "$RUNTIME_DIR/Input"
xcrun swift -module-cache-path "$RUNTIME_DIR/SwiftModuleCache" \
    "$ROOT_DIR/UITests/native-input.swift" "$RUNTIME_DIR" \
    > "$RUN_DIR/native-input.log" 2>&1 &
INPUT_PID=$!
trap 'kill "$INPUT_PID" 2>/dev/null || true; wait "$INPUT_PID" 2>/dev/null || true' EXIT
for ((attempt = 0; attempt < 300; attempt++)); do
    [[ -f "$RUNTIME_DIR/Input/ready" ]] && break
    if ! kill -0 "$INPUT_PID" 2>/dev/null; then
        cat "$RUN_DIR/native-input.log" >&2
        printf '1\n' > "$RUN_DIR/exit-code.txt"
        exit 1
    fi
    sleep 0.1
done
if [[ ! -f "$RUNTIME_DIR/Input/ready" ]]; then
    printf 'Native input helper did not become ready; see native-input.log.\n' >&2
    printf '1\n' > "$RUN_DIR/exit-code.txt"
    exit 1
fi
set +e
xcodebuild test \
    -project "$ROOT_DIR/UITests/InvokerUITests.xcodeproj" \
    -scheme InvokerUITests \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$RUNTIME_DIR/DerivedData" \
    -resultBundlePath "$RUN_DIR/Results.xcresult" \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -maximum-test-execution-time-allowance 90 \
    "INVOKER_UI_TEST_RUN_ROOT=$RUNTIME_DIR" \
    2>&1 | tee "$RUN_DIR/xcodebuild.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

printf '%s\n' "$TEST_STATUS" > "$RUN_DIR/exit-code.txt"
INPUT_DIRECTORY="$(cat "$RUNTIME_DIR/Input/container-directory.txt")"
if [[ -d "$INPUT_DIRECTORY" ]]; then
    cp -R "$INPUT_DIRECTORY" "$RUN_DIR/Input" || printf 'Input archive failed; originals retained at %s.\n' "$INPUT_DIRECTORY" >&2
fi
cp "$RUNTIME_DIR/Input/container-directory.txt" "$RUN_DIR/native-input-directory.txt"
if [[ -d "$RUNTIME_DIR/Data" ]]; then
    if ! cp -R "$RUNTIME_DIR/Data" "$RUN_DIR/Data"; then
        printf 'Data archive failed; originals retained at %s.\n' "$RUNTIME_DIR" >&2
    fi
fi
if [[ -d "$RUN_DIR/Results.xcresult" ]]; then
    if ! xcrun xcresulttool export attachments \
        --path "$RUN_DIR/Results.xcresult" \
        --output-path "$RUN_DIR/Attachments" \
        > "$RUN_DIR/attachments-export.log" 2>&1; then
        printf 'Attachment export failed; see attachments-export.log.\n' >&2
    fi
fi
printf 'UI test exit code: %s\nEvidence: %s\n' "$TEST_STATUS" "$RUN_DIR"
exit "$TEST_STATUS"
