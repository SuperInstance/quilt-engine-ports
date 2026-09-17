#!/usr/bin/env bash
# ci.sh — headless CI runner for the quilt-engine-ports Godot scaffold.
#
# Runs the GDScript assertions from `tests/assert_laws_test.gd` under
# Godot's headless mode, downloads a headless Godot binary if missing,
# and exits 0 on pass / 1 on fail.
#
# Implements the C1-C5 conformance rung from docs/DESIGN.md §3, which
# is the gate DESIGN.md §6 names for the Unity / Unreal ladder rungs.
#
# Usage:   scripts/ci.sh              # run all assertions
#          scripts/ci.sh --download   # force re-download of headless Godot
#          GODOT=/path/to/godot scripts/ci.sh
#
# Author: cowboy@superinstance.dev (Phase 216)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GODOT_BIN_DIR="$REPO_ROOT/.bin"
GODOT_VERSION="${GODOT_VERSION:-4.3-stable}"
HEADLESS_BIN="$GODOT_BIN_DIR/godot-headless"

# --- arg parse ---------------------------------------------------------

FORCE_DOWNLOAD=0
for arg in "$@"; do
    case "$arg" in
        --download) FORCE_DOWNLOAD=1 ;;
        --help|-h)
            sed -n '2,20p' "$0"
            exit 0 ;;
        *) echo "unknown arg: $arg"; exit 2 ;;
    esac
done

# --- locate or download Godot ----------------------------------------

download_godot() {
    mkdir -p "$GODOT_BIN_DIR"
    local url="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
    local zip="$GODOT_BIN_DIR/godot.zip"
    echo "  downloading $url"
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail -o "$zip" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$zip" "$url"
    else
        echo "ERROR: need curl or wget"
        exit 1
    fi
    unzip -o -q "$zip" -d "$GODOT_BIN_DIR"
    # zip extracts to a directory; find the headless-capable binary
    local extracted
    extracted="$(find "$GODOT_BIN_DIR" -name 'Godot*' -type f -executable | head -1)"
    if [ -z "$extracted" ]; then
        echo "ERROR: extracted binary not found"
        exit 1
    fi
    mv "$extracted" "$HEADLESS_BIN"
    chmod +x "$HEADLESS_BIN"
    rm -rf "$GODOT_BIN_DIR"/*.zip "$GODOT_BIN_DIR"/Godot*
    echo "  installed to $HEADLESS_BIN"
}

if [ -n "${GODOT:-}" ] && [ -x "$GODOT" ]; then
    GODOT_BIN="$GODOT"
elif [ -x "$HEADLESS_BIN" ] && [ "$FORCE_DOWNLOAD" -eq 0 ]; then
    GODOT_BIN="$HEADLESS_BIN"
else
    download_godot
    GODOT_BIN="$HEADLESS_BIN"
fi

# --- run all test scenes ----------------------------------------------

echo "=== quilt-engine-ports headless CI ==="
echo "  Godot:  $GODOT_BIN"
echo

ALL_PASS=1
for SCENE in laws_test world_cell_test cutting_edge_test; do
    echo "--- $SCENE ---"
    "$GODOT_BIN" --headless --path "$REPO_ROOT/godot" \
        "res://tests/$SCENE.tscn" \
        --quit-after 30 \
        2>&1 | tee -a "$REPO_ROOT/.bin/ci.log"
    EXIT=$?
    if [ $EXIT -ne 0 ]; then
        ALL_PASS=0
        echo "  -> $SCENE FAIL (exit $EXIT)"
    else
        echo "  -> $SCENE PASS"
    fi
done

if [ $ALL_PASS -eq 1 ]; then
    echo
    echo "=== CI PASS (all 3 scenes) ==="
    exit 0
else
    echo
    echo "=== CI FAIL ==="
    exit 1
fi
