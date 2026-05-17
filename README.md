# vortex-unthrottle

**Patch Vortex Mod Manager to bypass Nexus Mods download speed throttle.**

Nexus Mods caps download speeds for free accounts. Vortex enforces this with a client-side throttle — a byte-per-second limiter that drips chunks at whatever rate the Nexus API says you're allowed.

This tool patches Vortex's `app.asar` (its Electron bundle) to force the throttle cap to zero. Result: every download runs at your actual line speed. No proxy, no workarounds, no manual file links.

## How it works

Vortex bundles a `throttle.ts` → compiled into `renderer.js` inside `app.asar`. The relevant logic:

```js
const bps = getBPS();           // Nexus says: 1.5 MB/s for you, peasant
if (bps === 0) return next();   // if no cap, just go
// ...otherwise drip chunks at bps rate
```

Patch changes it to:

```js
const bps = 0;                  // unlimited
if (bps === 0) return next();   // always true now — full speed
```

## Usage

### Windows

```powershell
# Patch (default Vortex install)
.\unthrottle.ps1

# Custom install path
.\unthrottle.ps1 -VortexPath "D:\Games\Vortex"

# Restore original
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

### Manual (if scripts don't work)

```powershell
# Backup
copy "resources\app.asar" "resources\app.asar.bak"

# Unpack
npx @electron/asar extract app.asar _unpacked

# Edit _unpacked\renderer.js — find and replace any getBPS() call with 0
# Then repack
npx @electron/asar pack _unpacked app.asar
```

## What about Vortex updates?

Vortex updates will overwrite `app.asar`. After an update, re-run the script. The backup persists so you can always restore.

## Disclaimer

This modifies Vortex's internal code. Not endorsed by Black Tree Gaming or Nexus Mods. Use at your own risk. If Vortex breaks after an update, restore the backup and wait for a patch update.

---

**License:** MIT
