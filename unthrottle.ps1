<#
.SYNOPSIS
    Patches Vortex Mod Manager to bypass Nexus Mods download speed throttle.

.DESCRIPTION
    Unpacks Vortex's app.asar (Electron bundle), patches the client-side throttle
    in the download engine, and repacks. Downloads will run at full line speed
    regardless of Nexus Mods account tier.

    The throttle lives in the renderer process — it reads a bytes-per-second cap
    from the Nexus API response and enforces a slow drip. This patch forces the
    cap to always be zero (unlimited), so every chunk passes instantly.

.PARAMETER VortexPath
    Path to Vortex installation root.
    Default: C:\Program Files\Black Tree Gaming Ltd\Vortex

.PARAMETER Restore
    Restore the original app.asar from backup instead of patching.

.EXAMPLE
    .\unthrottle.ps1
    Patches Vortex at the default install path.

.EXAMPLE
    .\unthrottle.ps1 -Restore
    Restores the backup, undoing the patch.

.EXAMPLE
    .\unthrottle.ps1 -VortexPath "D:\Games\Vortex"
    Patches a custom Vortex install location.
#>

param(
    [string]$VortexPath = "C:\Program Files\Black Tree Gaming Ltd\Vortex",
    [switch]$Restore
)

$ErrorActionPreference = "Stop"
$asarPath = Join-Path $VortexPath "resources\app.asar"
$asarBak  = Join-Path $VortexPath "resources\app.asar.bak"
$workDir  = Join-Path $env:TEMP "vortex-unthrottle"

# ── Restore mode ──────────────────────────────────────────────
if ($Restore) {
    if (-not (Test-Path $asarBak)) {
        Write-Host "No backup found at $asarBak — nothing to restore." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "Restoring original app.asar from backup..." -ForegroundColor Cyan
    Copy-Item -Path $asarBak -Destination $asarPath -Force
    Write-Host "Done. Vortex is back to stock. Close and reopen Vortex." -ForegroundColor Green
    exit 0
}

# ── Pre-checks ────────────────────────────────────────────────
if (-not (Test-Path $asarPath)) {
    Write-Host "app.asar not found at $asarPath. Is Vortex installed? Use -VortexPath to point to the right location." -ForegroundColor Red
    exit 1
}

# Backup if not already done
if (-not (Test-Path $asarBak)) {
    Copy-Item -Path $asarPath -Destination $asarBak
    Write-Host "Backed up original to app.asar.bak" -ForegroundColor Cyan
}

# Check for asar CLI
$npx = Get-Command npx -ErrorAction SilentlyContinue
if (-not $npx) {
    Write-Host "npx not found. Install Node.js from https://nodejs.org" -ForegroundColor Red
    exit 1
}

# ── Unpack ────────────────────────────────────────────────────
Write-Host "Unpacking app.asar..." -ForegroundColor Cyan
if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir }
New-Item -ItemType Directory -Path $workDir | Out-Null

Push-Location $workDir
try {
    npx @electron/asar extract $asarPath . 2>&1 | Out-Null
    if (-not (Test-Path "renderer.js")) {
        Write-Host "Unpack failed — renderer.js not found." -ForegroundColor Red
        exit 1
    }
    Write-Host "Unpacked OK." -ForegroundColor Green

    # ── Patch ──────────────────────────────────────────────────
    Write-Host "Patching throttle..." -ForegroundColor Cyan

    $renderer = Get-Content "renderer.js" -Raw

    # The throttle code: const bps=getBPS();if(0===bps)return callback(null,chunk)
    # We force bps to always be 0, so every chunk sails through.
    #
    # Pattern to match (minified, with surrounding context for uniqueness):
    # throttle((e=>{const n=t.getBPS() ...
    #
    # Strategy: replace `getBPS()` call result with literal 0.
    # Looking for: getBPS()  or  t.getBPS()

    $patterns = @(
        # Pattern 1: direct call — const bps=getBPS()
        @{
            Find = 'const bps=getBPS()'
            Replace = 'const bps=0      '
        }
        # Pattern 2: method call — const bps=t.getBPS()
        @{
            Find = 'return t.getBPS()'
            Replace = 'return 0          '
        }
        # Pattern 3: inline in ternary — n=t.getBPS()
        @{
            Find = '=t.getBPS()'
            Replace = '=0          '
        }
    )

    $patched = $false
    foreach ($p in $patterns) {
        if ($renderer.Contains($p.Find)) {
            $renderer = $renderer.Replace($p.Find, $p.Replace)
            $patched = $true
            Write-Host "  Patched: $($p.Find)" -ForegroundColor Green
        }
    }

    if (-not $patched) {
        Write-Host "Throttle patterns not found — maybe Vortex updated? Check renderer.js manually for 'getBPS' or 'throttle'." -ForegroundColor Yellow
        # Still try to repack — might already be patched or different version
    }

    # Write patched renderer back
    Set-Content -Path "renderer.js" -Value $renderer -NoNewline

    # ── Repack ─────────────────────────────────────────────────
    Write-Host "Repacking app.asar..." -ForegroundColor Cyan
    npx @electron/asar pack . $asarPath 2>&1

    Write-Host "Done." -ForegroundColor Green
    Write-Host ""
    Write-Host "Close and reopen Vortex for the patch to take effect." -ForegroundColor Yellow
    Write-Host "To undo:  .\unthrottle.ps1 -Restore" -ForegroundColor Yellow
}
finally {
    Pop-Location
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
}
