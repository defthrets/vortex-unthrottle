# vortex-unthrottle

**Patch Vortex Mod Manager to bypass Nexus Mods download restrictions.**

Nexus Mods caps free accounts at ~3 MB/s per connection on their CDN. Vortex makes it worse — free users are locked to a single download worker and gated out of parallel downloads. You're downloading a 2 GB mod at 3 MB/s on a gigabit line.

This tool patches Vortex's `app.asar` to remove Vortex's *own* restrictions:

1. **Remove the premium gate on parallel downloads** — queue up to 3 files at once
2. **Remove the worker cap on chunks** — lets Vortex use all available chunks
3. **Bump defaults** — 16 chunks, 3 parallel downloads

## What it can and can't do

**What improves:**
- Multiple files download simultaneously (3 at once) — 3 x 3 MB/s = **~9 MB/s across queued mods**
- Large mod collections finish ~3x faster since files run in parallel

**What it can't do:**
- Single file speed is still capped at ~3 MB/s. Nexus CDN (Cloudflare) doesn't support HTTP Range requests for free accounts, so a single file can't be split across multiple connections. Only Nexus Premium lifts this cap.

**Optional proxy:** `Vortex-Unthrottle.bat` also starts a local proxy (`nexus-fast-proxy.js`) that attempts parallel Range requests on Nexus CDN. If Cloudflare honors them (rare), single files get 12x speed. If not (usual), it passes through with zero impact. The proxy only touches Nexus CDN traffic — everything else goes straight through.

## How it works

Vortex has a download manager with chunked downloading. The bottlenecks:

```js
// Free accounts: maxWorkers = 1
// So maxChunks = min(10, 1) = 1
maxChunks = Math.min(this.mMaxChunks, this.mMaxWorkers)

// Premium gate on parallel downloads
maxParallelDownloads = isPremium ? settings.maxParallelDownloads : 1
```

The fix: remove both gates, bump defaults. Multi-file queues fly. Single files are still bound by the CDN.

## Quick Install (Windows)

1. Install [Node.js](https://nodejs.org) if you don't have it
2. Download [`Vortex-Unthrottle.bat`](https://github.com/defthrets/vortex-unthrottle/raw/main/Vortex-Unthrottle.bat)
3. Drop it on your desktop
4. **Close Vortex**, then double-click the .bat
5. Reopen Vortex

The .bat always pulls the latest version from this repo before running. After Vortex updates, just click it again.

## Usage

### Windows

```powershell
# One-click (downloads latest, patches, done)
.\Vortex-Unthrottle.bat

# Manual --- patch (default Vortex install)
.\unthrottle.ps1

# Manual --- custom install path
.\unthrottle.ps1 -VortexPath "D:\Games\Vortex"

# Manual --- restore original
.\unthrottle.ps1 -Restore
```

**Requirements:** Node.js installed (`npx` available on PATH).

Close and reopen Vortex after patching.

### Linux / Steam Deck / Wine

```bash
chmod +x unthrottle.sh
./unthrottle.sh "/path/to/Vortex"

# Restore
./unthrottle.sh --restore
```

## Vortex updates

Vortex updates overwrite `app.asar`. After an update, re-run the script. The backup persists.

## Disclaimer

This modifies Vortex's internal code. Not endorsed by Black Tree Gaming or Nexus Mods. Use at your own risk.

---

**License:** MIT
