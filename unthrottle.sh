#!/usr/bin/env bash
# unthrottle.sh — Patch Vortex to bypass Nexus Mods download speed caps
# Linux / Steam Deck / Wine/Proton version
#
# Usage:
#   ./unthrottle.sh                          # Patch default Vortex install
#   ./unthrottle.sh "/path/to/Vortex"        # Custom path
#   ./unthrottle.sh --restore                # Undo all patches

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

VORTEX_PATH="${1:-}"
RESTORE=false

if [[ "$VORTEX_PATH" == "--restore" ]]; then
    RESTORE=true
    for guess in \
        "$HOME/.local/share/Steam/steamapps/compatdata/"*"/pfx/drive_c/Program Files/Black Tree Gaming Ltd/Vortex" \
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
echo -e "${CYAN}Patching download manager...${NC}"
PATCHED=false

# Patch 1: Remove maxWorkers cap on chunks (THE key fix)
# Before: maxChunks=Math.min(this.mMaxChunks,this.mMaxWorkers)
# After:  maxChunks=this.mMaxChunks
if grep -q "maxChunks=Math.min(this.mMaxChunks,this.mMaxWorkers)" renderer.js; then
    sed -i 's/maxChunks=Math\.min(this\.mMaxChunks,this\.mMaxWorkers)/maxChunks=this.mMaxChunks/' renderer.js
    echo -e "  ${GREEN}Patch 1: removed worker cap on chunks${NC}"
    PATCHED=true
fi

# Patch 2: Remove premium gate on maxParallelDownloads
if grep -q "maxParallelDownloads=!0===state.persistent.nexus?.userInfo?.isPremium?state.settings.downloads.maxParallelDownloads:1" renderer.js; then
    sed -i 's/maxParallelDownloads=!0===state\.persistent\.nexus?\.userInfo?\.isPremium?state\.settings\.downloads\.maxParallelDownloads:1/maxParallelDownloads=state.settings.downloads.maxParallelDownloads/' renderer.js
    echo -e "  ${GREEN}Patch 2: removed premium gate on parallel downloads${NC}"
    PATCHED=true
fi

# Patch 3: Remove premium gate on parallelDownloads (UI)
if grep -q "parallelDownloads:isPremium?state.settings.downloads.maxParallelDownloads:1" renderer.js; then
    sed -i 's/parallelDownloads:isPremium?state\.settings\.downloads\.maxParallelDownloads:1/parallelDownloads:state.settings.downloads.maxParallelDownloads/' renderer.js
    echo -e "  ${GREEN}Patch 3: removed premium gate on parallel downloads (UI)${NC}"
    PATCHED=true
fi

# Patch 4: Bump maxParallelDownloads default 1→3
if grep -q "maxParallelDownloads:1," renderer.js; then
    sed -i 's/maxParallelDownloads:1,/maxParallelDownloads:3,/' renderer.js
    echo -e "  ${GREEN}Patch 4: bumped maxParallelDownloads 1→3${NC}"
    PATCHED=true
fi

# Patch 5: Bump maxChunks default 10→16
if grep -q "maxChunks:10," renderer.js; then
    sed -i 's/maxChunks:10,/maxChunks:16,/' renderer.js
    echo -e "  ${GREEN}Patch 5: bumped maxChunks 10→16${NC}"
    PATCHED=true
fi

if ! $PATCHED; then
    echo -e "${YELLOW}No patterns matched — Vortex may have updated.${NC}"
    echo -e "${YELLOW}Check renderer.js for 'maxChunks', 'maxParallelDownloads', 'isPremium'.${NC}"
fi

# ── Repack ────────────────────────────────────────────────────
echo -e "${CYAN}Repacking app.asar...${NC}"
npx @electron/asar pack . "$ASAR"

rm -rf "$WORK"

echo -e "${GREEN}Done.${NC}"
echo ""
echo -e "${YELLOW}Close and reopen Vortex for the patch to take effect.${NC}"
echo -e "${YELLOW}To undo:  ./unthrottle.sh --restore${NC}"
