#!/usr/bin/env bash
# unthrottle.sh — Patch Vortex Mod Manager to bypass Nexus Mods download throttle
# Linux / Steam Deck / Wine/Proton version
#
# Usage:
#   ./unthrottle.sh                          # Patch default Vortex install
#   ./unthrottle.sh "/path/to/Vortex"        # Custom path
#   ./unthrottle.sh --restore                # Undo the patch

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

VORTEX_PATH="${1:-}"
RESTORE=false

if [[ "$VORTEX_PATH" == "--restore" ]]; then
    RESTORE=true
    # Find Vortex from common paths
    for guess in \
        "$HOME/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/Program Files/Black Tree Gaming Ltd/Vortex" \
        "$HOME/.wine/drive_c/Program Files/Black Tree Gaming Ltd/Vortex" \
        "/mnt/c/Program Files/Black Tree Gaming Ltd/Vortex"; do
        if [ -d "$guess" ]; then VORTEX_PATH="$guess"; break; fi
    done
fi

if [ -z "$VORTEX_PATH" ]; then
    echo "Usage: $0 [path-to-vortex] | --restore"
    exit 1
fi

ASAR="$VORTEX_PATH/resources/app.asar"
BAK="$VORTEX_PATH/resources/app.asar.bak"
WORK="$(mktemp -d)"

# ── Restore ───────────────────────────────────────────────────
if $RESTORE; then
    if [ ! -f "$BAK" ]; then
        echo -e "${RED}No backup at $BAK — nothing to restore.${NC}"
        exit 1
    fi
    echo -e "${CYAN}Restoring original...${NC}"
    cp "$BAK" "$ASAR"
    echo -e "${GREEN}Done. Close and reopen Vortex.${NC}"
    exit 0
fi

# ── Pre-checks ────────────────────────────────────────────────
if [ ! -f "$ASAR" ]; then
    echo -e "${RED}app.asar not found at $ASAR${NC}"
    exit 1
fi

if ! command -v npx &>/dev/null; then
    echo -e "${RED}npx not found. Install Node.js first.${NC}"
    exit 1
fi

# Backup
if [ ! -f "$BAK" ]; then
    cp "$ASAR" "$BAK"
    echo -e "${CYAN}Backed up original.${NC}"
fi

# ── Unpack ────────────────────────────────────────────────────
echo -e "${CYAN}Unpacking app.asar...${NC}"
npx @electron/asar extract "$ASAR" "$WORK"
cd "$WORK"

if [ ! -f "renderer.js" ]; then
    echo -e "${RED}Unpack failed — renderer.js not found.${NC}"
    rm -rf "$WORK"
    exit 1
fi

# ── Patch ─────────────────────────────────────────────────────
echo -e "${CYAN}Patching throttle...${NC}"
PATCHED=false

for pattern in \
    's/const bps=getBPS()/const bps=0       /' \
    's/return t\.getBPS()/return 0          /' \
    's/=t\.getBPS()/=0          /'; do

    if grep -q "$(echo "$pattern" | sed 's|s/||; s|/.*||')" renderer.js; then
        sed -i "$pattern" renderer.js
        echo -e "  ${GREEN}Patched: $pattern${NC}"
        PATCHED=true
    fi
done

if ! $PATCHED; then
    echo -e "${YELLOW}No throttle patterns matched — Vortex may have changed.${NC}"
    echo -e "${YELLOW}Check renderer.js for 'getBPS' or 'throttle'.${NC}"
fi

# ── Repack ────────────────────────────────────────────────────
echo -e "${CYAN}Repacking app.asar...${NC}"
npx @electron/asar pack . "$ASAR"

rm -rf "$WORK"

echo -e "${GREEN}Done.${NC}"
echo ""
echo -e "${YELLOW}Close and reopen Vortex for the patch to take effect.${NC}"
echo -e "${YELLOW}To undo:  ./unthrottle.sh --restore${NC}"
