# vortex-unthrottle

**Patch Vortex Mod Manager to bypass Nexus Mods download speed caps.**

Nexus Mods caps free accounts at ~1.5–3 MB/s per connection server-side. Vortex makes it worse — free users are locked to a single download worker, so files use ONE connection at that capped speed. You're downloading a 2 GB mod at 1.5 MB/s on a gigabit line.

This tool patches Vortex's `app.asar` to:

1. **Remove the worker cap on chunks** — all 16 connections fire at once
2. **Remove the premium gate on parallel downloads**
3. **Bump defaults** — 16 chunks per file, 3 files in parallel

Result: each file uses 16 simultaneous CDN connections at 1.5–3 MB/s each = **24–48 MB/s per file**.

## How it works

Vortex has a download manager with chunked downloading. The bottleneck:

```js
// Free accounts: maxWorkers = 1
// So maxChunks = min(10, 1) = 1 — single connection!
maxChunks = Math.min(this.mMaxChunks, this.mMaxWorkers)

// Premium gate on parallel downloads
maxParallelDownloads = isPremium ? settings.maxParallelDownloads : 1
```

The fix: remove the worker cap, kill the premium gate, bump defaults.

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

# Manual — patch (default Vortex install)
.\unthrottle.ps1

# Manual — custom install path
.\unthrottle.ps1 -VortexPath "D:\Games\Vortex"

# Manual — restore original
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
