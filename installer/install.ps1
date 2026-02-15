#Requires -Version 5.1
<#
.SYNOPSIS
    TrueAsync PHP Installer for Windows.
.DESCRIPTION
    Downloads and installs TrueAsync PHP on Windows.
    Usage: irm https://raw.githubusercontent.com/true-async/releases/main/installer/install.ps1 | iex
.NOTES
    Set $env:INSTALL_DIR to customize installation path.
    Set $env:VERSION to install a specific version (e.g., "v0.1.0").
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Repo = "true-async/releases"
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { "$env:LOCALAPPDATA\php-trueasync" }
$Version = if ($env:VERSION) { $env:VERSION } else { "latest" }
$SkipVerify = $env:SKIP_VERIFY -eq "true"

function Write-Info  { param($msg) Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline; Write-Host $msg }
function Write-Ok    { param($msg) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Write-Warn  { param($msg) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err   { param($msg) Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $msg; exit 1 }

# --- Get latest version ---
function Get-LatestVersion {
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    $response = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "TrueAsync-Installer" }
    return $response.tag_name
}

# --- Verify SHA256 ---
function Test-Checksum {
    param(
        [string]$File,
        [string]$Expected
    )

    $actual = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToLower()
    $expected = $Expected.ToLower()

    if ($actual -ne $expected) {
        Write-Err "Checksum mismatch!`n  Expected: $expected`n  Actual:   $actual"
    }

    Write-Ok "Checksum verified"
}

# === Main ===
function Main {
    Write-Host ""
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "   TrueAsync PHP Installer" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host ""

    $platform = "windows-x64"
    Write-Info "Platform: $platform"

    # Resolve version
    if ($Version -eq "latest") {
        Write-Info "Fetching latest version..."
        $Version = Get-LatestVersion
        if (-not $Version) {
            Write-Err "Could not determine latest version"
        }
    }

    $versionNum = $Version.TrimStart("v")
    Write-Info "Version: $Version"

    # Determine archive
    $archive = "php-trueasync-${versionNum}-${platform}.zip"
    $baseUrl = "https://github.com/$Repo/releases/download/$Version"
    $archiveUrl = "$baseUrl/$archive"
    $checksumsUrl = "$baseUrl/sha256sums.txt"

    # Create temp directory
    $tmpDir = Join-Path $env:TEMP "php-trueasync-install-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    try {
        # Download archive
        Write-Info "Downloading $archive..."
        $archivePath = Join-Path $tmpDir $archive
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing
        Write-Ok "Downloaded"

        # Verify checksum
        if (-not $SkipVerify) {
            Write-Info "Downloading checksums..."
            $checksumsPath = Join-Path $tmpDir "sha256sums.txt"
            Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumsPath -UseBasicParsing

            $checksumLine = Get-Content $checksumsPath | Where-Object { $_ -match $archive }
            if ($checksumLine) {
                $expected = ($checksumLine -split '\s+')[0]
                Test-Checksum -File $archivePath -Expected $expected
            } else {
                Write-Warn "Checksum for $archive not found in sha256sums.txt"
            }
        }

        # Install
        Write-Info "Installing to $InstallDir..."

        if (Test-Path $InstallDir) {
            Remove-Item -Recurse -Force $InstallDir
        }
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

        Expand-Archive -Path $archivePath -DestinationPath $InstallDir -Force
        Write-Ok "Installed to $InstallDir"

        # Add to PATH
        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($currentPath -notlike "*php-trueasync*") {
            [Environment]::SetEnvironmentVariable("Path", "$InstallDir;$currentPath", "User")
            $env:Path = "$InstallDir;$env:Path"
            Write-Ok "Added $InstallDir to user PATH"
            Write-Warn "Restart your terminal for PATH changes to take effect"
        }

        # Verify
        Write-Host ""
        Write-Info "Verifying installation..."
        $phpExe = Join-Path $InstallDir "php.exe"
        if (Test-Path $phpExe) {
            & $phpExe -v
            Write-Host ""
            Write-Ok "TrueAsync PHP installed successfully!"
        } else {
            # Try nested directory
            $phpExe = Get-ChildItem -Path $InstallDir -Recurse -Filter "php.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($phpExe) {
                & $phpExe.FullName -v
                Write-Host ""
                Write-Ok "TrueAsync PHP installed successfully!"
                Write-Warn "PHP binary found at: $($phpExe.FullName)"
            } else {
                Write-Warn "php.exe not found in $InstallDir — check the archive structure"
            }
        }
    }
    finally {
        # Cleanup
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }

    Write-Host ""
}

Main
