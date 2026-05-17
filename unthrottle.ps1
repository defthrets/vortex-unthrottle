<#
.SYNOPSIS
    Patches Vortex Mod Manager to bypass Nexus Mods download speed caps.

.DESCRIPTION
    Nexus Mods caps free accounts at ~1.5-3 MB/s per connection server-side.
    Vortex enforces this further by limiting free users to a single download
    worker, which means files use ONE connection at that capped speed.

    This script patches Vortex's app.asar (Electron bundle) to:
    1. Remove the worker cap on download chunks — all 16 connections fire at once
    2. Remove the premium-only gate on parallel downloads
    3. Bump defaults: 16 chunks/file, 3 parallel downloads

    Result: each file uses 16 simultaneous CDN connections at 1.5-3 MB/s each
    = 24-48 MB/s per file, up to 3 files in parallel.

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
    Restores the backup, undoing all patches.

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
    Write-Host "Patching download manager..." -ForegroundColor Cyan

    $renderer = Get-Content "renderer.js" -Raw
    $patched = $false

    # Patch 1: Remove maxWorkers cap on chunks
    # Before: maxChunks=Math.min(this.mMaxChunks,this.mMaxWorkers)
    # After:  maxChunks=this.mMaxChunks
    # This is the KEY fix — free accounts had maxWorkers=1, capping chunks to 1.
    $old = 'maxChunks=Math.min(this.mMaxChunks,this.mMaxWorkers)'
    $new = 'maxChunks=this.mMaxChunks'
    if ($renderer.Contains($old)) {
        $renderer = $renderer.Replace($old, $new)
        Write-Host "  Patch 1: removed worker cap on chunks" -ForegroundColor Green
        $patched = $true
    }

    # Patch 2: Remove premium gate on maxParallelDownloads (line ~2117)
    # Before: maxParallelDownloads=!0===state.persistent.nexus?.userInfo?.isPremium?state.settings.downloads.maxParallelDownloads:1
    # After:  maxParallelDownloads=state.settings.downloads.maxParallelDownloads
    $old = 'maxParallelDownloads=!0===state.persistent.nexus?.userInfo?.isPremium?state.settings.downloads.maxParallelDownloads:1'
    $new = 'maxParallelDownloads=state.settings.downloads.maxParallelDownloads'
    if ($renderer.Contains($old)) {
        $renderer = $renderer.Replace($old, $new)
        Write-Host "  Patch 2: removed premium gate on parallel downloads (worker)" -ForegroundColor Green
        $patched = $true
    }

    # Patch 3: Remove premium gate on parallelDownloads (line ~2482)
    # Before: parallelDownloads:isPremium?state.settings.downloads.maxParallelDownloads:1
    # After:  parallelDownloads:state.settings.downloads.maxParallelDownloads
    $old = 'parallelDownloads:isPremium?state.settings.downloads.maxParallelDownloads:1'
    $new = 'parallelDownloads:state.settings.downloads.maxParallelDownloads'
    if ($renderer.Contains($old)) {
        $renderer = $renderer.Replace($old, $new)
        Write-Host "  Patch 3: removed premium gate on parallel downloads (UI)" -ForegroundColor Green
        $patched = $true
    }

    # Patch 4: Bump default maxParallelDownloads from 1 to 3
    $old = 'maxParallelDownloads:1,'
    $new = 'maxParallelDownloads:3,'
    if ($renderer.Contains($old)) {
        $renderer = $renderer.Replace($old, $new)
        Write-Host "  Patch 4: bumped maxParallelDownloads default 1→3" -ForegroundColor Green
        $patched = $true
    }

    # Patch 5: Bump default maxChunks from 10 to 16
    $old = 'maxChunks:10,'
    $new = 'maxChunks:16,'
    if ($renderer.Contains($old)) {
        $renderer = $renderer.Replace($old, $new)
        Write-Host "  Patch 5: bumped maxChunks default 10→16" -ForegroundColor Green
        $patched = $true
    }

    if (-not $patched) {
        Write-Host "No patterns matched — Vortex may have updated. Check renderer.js manually." -ForegroundColor Yellow
    }

    # Write patched renderer back
    Set-Content -Path "renderer.js" -Value $renderer -NoNewline

    # ── Repack ─────────────────────────────────────────────────
    Write-Host "Repacking app.asar..." -ForegroundColor Cyan
    npx @electron/asar pack . $asarPath 2>&1

    Write-Host ""
    Write-Host "Done. Close and reopen Vortex." -ForegroundColor Green
    Write-Host "To undo:  .\unthrottle.ps1 -Restore" -ForegroundColor Yellow
}
finally {
    Pop-Location
    Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue
}
