#!/bin/bash
# Bundle whisper-cli and its dependencies into the app

set -e

APP_BUNDLE="WhisperDictate.app"
FRAMEWORKS_DIR="$APP_BUNDLE/Contents/Frameworks"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"

# Find whisper-cli
WHISPER_CLI=$(which whisper-cli 2>/dev/null || echo "/opt/homebrew/bin/whisper-cli")
if [ ! -f "$WHISPER_CLI" ] && [ ! -L "$WHISPER_CLI" ]; then
    echo "Error: whisper-cli not found"
    exit 1
fi

# Resolve symlinks to get actual path
WHISPER_CLI_REAL=$(readlink -f "$WHISPER_CLI" 2>/dev/null || python3 -c "import os; print(os.path.realpath('$WHISPER_CLI'))")
WHISPER_LIB_DIR=$(dirname "$WHISPER_CLI_REAL")/../lib

# Create directories
mkdir -p "$FRAMEWORKS_DIR"

# Copy whisper-cli
cp "$WHISPER_CLI_REAL" "$MACOS_DIR/whisper-cli"
chmod +x "$MACOS_DIR/whisper-cli"

# Copy whisper-server (warm, preloaded-model HTTP backend) from the same bin dir
WHISPER_BIN_DIR=$(dirname "$WHISPER_CLI_REAL")
WHISPER_SERVER_REAL="$WHISPER_BIN_DIR/whisper-server"
if [ -f "$WHISPER_SERVER_REAL" ]; then
    cp "$WHISPER_SERVER_REAL" "$MACOS_DIR/whisper-server"
    chmod +x "$MACOS_DIR/whisper-server"
    echo "Copied: whisper-server"
else
    echo "Warning: whisper-server not found at $WHISPER_SERVER_REAL"
fi

# List of dylibs to copy
DYLIBS=(
    "libwhisper.1.dylib"
    "libggml.0.dylib"
    "libggml-cpu.0.dylib"
    "libggml-blas.0.dylib"
    "libggml-metal.0.dylib"
    "libggml-base.0.dylib"
)

# Copy dylibs (resolve symlinks)
for dylib in "${DYLIBS[@]}"; do
    src="$WHISPER_LIB_DIR/$dylib"
    if [ -L "$src" ]; then
        src=$(readlink -f "$src" 2>/dev/null || python3 -c "import os; print(os.path.realpath('$src'))")
    fi
    if [ -f "$src" ]; then
        cp "$src" "$FRAMEWORKS_DIR/$dylib"
        echo "Copied: $dylib"
    else
        echo "Warning: $dylib not found at $src"
    fi
done

# Fix dylib paths in the bundled executables (whisper-cli + whisper-server)
for exe in whisper-cli whisper-server; do
    [ -f "$MACOS_DIR/$exe" ] || continue
    for dylib in "${DYLIBS[@]}"; do
        install_name_tool -change "@rpath/$dylib" "@executable_path/../Frameworks/$dylib" "$MACOS_DIR/$exe" 2>/dev/null || true
    done
done

# Fix dylib paths in each dylib (they reference each other)
for dylib in "${DYLIBS[@]}"; do
    if [ -f "$FRAMEWORKS_DIR/$dylib" ]; then
        # Change the dylib's own ID
        install_name_tool -id "@executable_path/../Frameworks/$dylib" "$FRAMEWORKS_DIR/$dylib" 2>/dev/null || true

        # Fix references to other dylibs
        for other in "${DYLIBS[@]}"; do
            install_name_tool -change "@rpath/$other" "@executable_path/../Frameworks/$other" "$FRAMEWORKS_DIR/$dylib" 2>/dev/null || true
        done
    fi
done

# Sign everything (ad-hoc; the release flow re-signs with Developer ID afterward)
for exe in whisper-cli whisper-server; do
    [ -f "$MACOS_DIR/$exe" ] && codesign --force --sign - "$MACOS_DIR/$exe" 2>/dev/null || true
done
for dylib in "${DYLIBS[@]}"; do
    codesign --force --sign - "$FRAMEWORKS_DIR/$dylib" 2>/dev/null || true
done

echo "✓ Bundled whisper-cli and dependencies"
