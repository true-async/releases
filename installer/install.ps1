#Requires -Version 5.1
<#
.SYNOPSIS
    TrueAsync PHP Installer for Windows.
.DESCRIPTION
    Downloads and installs TrueAsync PHP on Windows.

    Install:   irm https://raw.githubusercontent.com/true-async/releases/main/installer/install.ps1 | iex
    Update:    php-trueasync update
    Uninstall: php-trueasync uninstall
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
$VersionFile = ".trueasync-version"
$Command = if ($env:TRUEASYNC_CMD) { $env:TRUEASYNC_CMD } else { "install" }

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

# --- Get installed version ---
function Get-InstalledVersion {
    $vfile = Join-Path $InstallDir $VersionFile
    if (Test-Path $vfile) {
        return (Get-Content $vfile -Raw).Trim()
    }
    return ""
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

# --- Install management script ---
function Install-ManagementScript {
    $scriptPath = Join-Path $InstallDir "php-trueasync.cmd"

    $scriptContent = @'
@echo off
setlocal

set "INSTALL_DIR=%~dp0"
set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
set "VERSION_FILE=%INSTALL_DIR%\.trueasync-version"

if "%1"=="" goto :help
if "%1"=="update" goto :update
if "%1"=="version" goto :version
if "%1"=="uninstall" goto :uninstall
if "%1"=="help" goto :help
if "%1"=="--help" goto :help
if "%1"=="-h" goto :help

echo Unknown command: %1
echo Run 'php-trueasync help' for usage.
exit /b 1

:update
echo Checking for updates...
if exist "%VERSION_FILE%" (
    set /p CURRENT=<"%VERSION_FILE%"
    echo Current version: %CURRENT%
) else (
    echo Current version: unknown
)
set "TRUEASYNC_CMD=update"
set "INSTALL_DIR=%INSTALL_DIR%"
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/true-async/releases/main/installer/install.ps1 | iex"
goto :eof

:version
if exist "%VERSION_FILE%" (
    type "%VERSION_FILE%"
) else (
    echo unknown
)
goto :eof

:uninstall
echo Uninstalling TrueAsync PHP from %INSTALL_DIR%...

REM Remove from PATH
for /f "tokens=*" %%a in ('powershell -Command "[Environment]::GetEnvironmentVariable('Path','User')"') do set "UPATH=%%a"
powershell -Command "$p=[Environment]::GetEnvironmentVariable('Path','User'); $p=($p -split ';' | Where-Object { $_ -notlike '*php-trueasync*' }) -join ';'; [Environment]::SetEnvironmentVariable('Path',$p,'User')"
echo Cleaned PATH

REM Schedule self-deletion
start /b cmd /c "timeout /t 1 /nobreak >nul & rd /s /q "%INSTALL_DIR%""
echo TrueAsync PHP uninstalled.
echo Restart your terminal to apply PATH changes.
goto :eof

:help
echo TrueAsync PHP Manager
echo.
echo Usage: php-trueasync ^<command^>
echo.
echo Commands:
echo   update      Check for updates and install the latest version
echo   version     Show the installed version
echo   uninstall   Remove TrueAsync PHP and clean up PATH
echo   help        Show this help message
goto :eof
'@

    Set-Content -Path $scriptPath -Value $scriptContent -Encoding ASCII
}

# --- Do install ---
function Do-Install {
    $platform = "windows-x64"
    Write-Info "Platform: $platform"

    # Resolve version
    if ($Version -eq "latest") {
        Write-Info "Fetching latest version..."
        $script:Version = Get-LatestVersion
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

            $checksumLine = Get-Content $checksumsPath | Where-Object { $_ -match [regex]::Escape($archive) }
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

        # Save version marker
        Set-Content -Path (Join-Path $InstallDir $VersionFile) -Value $Version

        Write-Ok "Installed to $InstallDir"

        # Install management script
        Install-ManagementScript

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
            Write-Ok "TrueAsync PHP $Version installed successfully!"
        } else {
            $phpExe = Get-ChildItem -Path $InstallDir -Recurse -Filter "php.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($phpExe) {
                & $phpExe.FullName -v
                Write-Host ""
                Write-Ok "TrueAsync PHP $Version installed successfully!"
                Write-Warn "PHP binary found at: $($phpExe.FullName)"
            } else {
                Write-Warn "php.exe not found in $InstallDir — check the archive structure"
            }
        }
    }
    finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }

    Write-Host ""
}

# --- Do update ---
function Do-Update {
    $current = Get-InstalledVersion

    if (-not $current) {
        Write-Info "No existing installation found. Running fresh install..."
        Do-Install
        return
    }

    Write-Info "Current version: $current"
    Write-Info "Checking for updates..."

    $latest = Get-LatestVersion

    if (-not $latest) {
        Write-Err "Could not determine latest version"
    }

    if ($current -eq $latest) {
        Write-Ok "Already up to date ($current)"
        return
    }

    Write-Info "New version available: $latest (current: $current)"
    $script:Version = $latest
    Do-Install
}

# --- Do uninstall ---
function Do-Uninstall {
    if (-not (Test-Path $InstallDir)) {
        Write-Warn "TrueAsync PHP is not installed at $InstallDir"
        return
    }

    Write-Info "Uninstalling TrueAsync PHP from $InstallDir..."

    # Remove from PATH
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($currentPath -split ';' | Where-Object { $_ -notlike "*php-trueasync*" }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Ok "Cleaned PATH"

    Remove-Item -Recurse -Force $InstallDir
    Write-Ok "TrueAsync PHP uninstalled"
    Write-Warn "Restart your terminal to apply PATH changes"
}

# === Main ===
function Main {
    Write-Host ""
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host "   TrueAsync PHP Installer" -ForegroundColor Cyan
    Write-Host "=================================" -ForegroundColor Cyan
    Write-Host ""

    switch ($Command) {
        "update"    { Do-Update }
        "uninstall" { Do-Uninstall }
        default     { Do-Install }
    }
}

Main
