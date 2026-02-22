#Requires -Version 5.1
<#
.SYNOPSIS
    TrueAsync PHP Installer for Windows.
.DESCRIPTION
    Downloads and installs TrueAsync PHP on Windows.

    Install:   irm https://raw.githubusercontent.com/true-async/releases/master/installer/install.ps1 | iex
    Update:    php-trueasync update
    Uninstall: php-trueasync uninstall
.NOTES
    Environment variables:
      INSTALL_DIR      Custom installation path
      VERSION          Specific version to install (e.g. "v0.1.0")
      PHP_VERSION      Specific PHP version (e.g. "8.6")
      SET_DEFAULT      "true"/"false" to control PATH (default: prompt)
      DEBUG_BUILD      "true" to install debug build (default: prompt)
      SKIP_VERIFY      "true" to skip checksum verification
      NON_INTERACTIVE  "true" to skip all prompts and use defaults
#>

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ── Config ───────────────────────────────────────────────────────────────────

$Repo        = "true-async/releases"
$DefaultDir  = Join-Path $env:LOCALAPPDATA "php-trueasync"
$InstallDir  = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { $DefaultDir }
$Version     = if ($env:VERSION)     { $env:VERSION }     else { "latest" }
$PhpVersion  = $env:PHP_VERSION
$SkipVerify  = $env:SKIP_VERIFY -eq "true"
$SetDefault  = $env:SET_DEFAULT   # "true" | "false" | empty = prompt
$DebugBuild  = $env:DEBUG_BUILD   # "true" | "false" | empty = prompt
$VersionFile = ".trueasync-version"
$Command     = if ($env:TRUEASYNC_CMD) { $env:TRUEASYNC_CMD } else { "install" }

try {
    $IsInteractive = [Environment]::UserInteractive -and
                     (-not ($env:NON_INTERACTIVE -eq "true")) -and
                     (-not [Console]::IsInputRedirected)
} catch {
    $IsInteractive = $false
}

# ── UI helpers ────────────────────────────────────────────────────────────────

$_step  = 0
$_total = 0

function Write-Header {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║   " -ForegroundColor Cyan -NoNewline
    Write-Host "TrueAsync PHP" -ForegroundColor White -NoNewline
    Write-Host " Installer" -ForegroundColor DarkGray -NoNewline
    Write-Host "            ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Set-TotalSteps { param($n) $script:_total = $n; $script:_step = 0 }

function Write-Pending {
    param([string]$Label)
    $script:_step++
    Write-Host ("  · [{0}/{1}]  {2}..." -f $script:_step, $script:_total, $Label) `
        -ForegroundColor DarkGray -NoNewline
}

function Write-Done {
    param([string]$Label, [string]$Detail = "", [string]$DetailColor = "DarkGray")
    Write-Host "`r  " -NoNewline
    Write-Host "✓" -ForegroundColor Green -NoNewline
    Write-Host (" [{0}/{1}]  {2}" -f $script:_step, $script:_total, $Label) -NoNewline
    if ($Detail) {
        Write-Host "  " -NoNewline
        Write-Host $Detail -ForegroundColor $DetailColor -NoNewline
    }
    Write-Host "          "  # trailing spaces to clear pending-line remnants + newline
}

function Write-StepFail {
    param([string]$Label, [string]$Detail = "")
    Write-Host "`r  " -NoNewline
    Write-Host "✗" -ForegroundColor Red -NoNewline
    Write-Host (" [{0}/{1}]  {2}" -f $script:_step, $script:_total, $Label) -NoNewline
    if ($Detail) { Write-Host "  $Detail" -ForegroundColor Red -NoNewline }
    Write-Host ""
}

function Write-Ok   { param($Msg); Write-Host "  " -NoNewline; Write-Host "✓" -ForegroundColor Green -NoNewline; Write-Host "  $Msg" }
function Write-Info { param($Msg); Write-Host "  " -NoNewline; Write-Host "·" -ForegroundColor DarkGray -NoNewline; Write-Host "  $Msg" -ForegroundColor DarkGray }
function Write-Warn { param($Msg); Write-Host "  " -NoNewline; Write-Host "!" -ForegroundColor Yellow -NoNewline; Write-Host "  $Msg" -ForegroundColor Yellow }

function Write-Fail {
    param($Msg)
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "✗" -ForegroundColor Red -NoNewline
    Write-Host "  $Msg" -ForegroundColor Red
    exit 1
}

function Write-Summary {
    param([System.Collections.Specialized.OrderedDictionary]$Items)
    $maxInner  = 70   # max inner width of the box
    $keyLen    = ($Items.Keys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $maxValLen = $maxInner - $keyLen - 7   # 7 = 2 left pad + 3 separator + 2 right pad

    # Truncate long values with ellipsis
    $rows = [ordered]@{}
    foreach ($e in $Items.GetEnumerator()) {
        $val = $e.Value
        if ($val.Length -gt $maxValLen) { $val = $val.Substring(0, $maxValLen - 3) + "..." }
        $rows[$e.Key] = $val
    }

    $valLen = ($rows.Values | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $inner  = $keyLen + $valLen + 7
    $border = "─" * $inner

    Write-Host ""
    Write-Host ("  ╭" + $border + "╮") -ForegroundColor DarkGray
    foreach ($e in $rows.GetEnumerator()) {
        Write-Host "  │  " -ForegroundColor DarkGray -NoNewline
        Write-Host ($e.Key.PadRight($keyLen)) -ForegroundColor DarkGray -NoNewline
        Write-Host "   " -NoNewline
        Write-Host ($e.Value.PadRight($valLen)) -NoNewline
        Write-Host "  │" -ForegroundColor DarkGray
    }
    Write-Host ("  ╰" + $border + "╯") -ForegroundColor DarkGray
    Write-Host ""
}

# Pre-install summary (rustup-style: show what WILL happen, before doing it)
function Write-PreInstall {
    param(
        [string]$Ver,
        [string]$Dir,
        [string]$Platform,
        [bool]$PathFlag,
        [bool]$Debug
    )
    $items = [ordered]@{}
    $items["Version"]  = $Ver
    $items["Build"]    = if ($Debug) { "debug" } else { "release" }
    $items["Platform"] = $Platform
    $items["Location"] = $Dir
    $items["PATH"]     = if ($PathFlag) { "will be added" } else { "skip" }
    Write-Summary $items
}

function Read-Input {
    param([string]$Prompt, [string]$Default = "")
    if (-not $IsInteractive) { return $Default }
    try {
        $val = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
        return $val.Trim()
    } catch { return $Default }
}

function Read-YesNo {
    param([string]$Prompt, [bool]$Default = $true)
    if (-not $IsInteractive) { return $Default }
    try {
        $hint = if ($Default) { "y/n [yes]" } else { "y/n [no]" }
        $val  = Read-Host "$Prompt $hint"
        if ([string]::IsNullOrWhiteSpace($val)) { return $Default }
        return $val -match "^[yY]"
    } catch { return $Default }
}

# ── Core functions ────────────────────────────────────────────────────────────

function Get-LatestVersion {
    $url      = "https://api.github.com/repos/$Repo/releases"
    $releases = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "TrueAsync-Installer" }
    if ($releases.Count -eq 0) { return $null }
    return $releases[0].tag_name
}

function Get-InstalledVersion {
    $vfile = Join-Path $InstallDir $VersionFile
    if (Test-Path $vfile) { return (Get-Content $vfile -Raw).Trim() }
    return ""
}

function Get-FormattedSize {
    param([string]$Path)
    $bytes = (Get-Item $Path).Length
    if ($bytes -ge 1MB) { return "{0:F1} MiB" -f ($bytes / 1MB) }
    return "{0:F0} KiB" -f ($bytes / 1KB)
}


function Test-Checksum {
    param([string]$File, [string]$Expected)
    $actual = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $Expected.ToLower()) {
        Write-StepFail "Checksum mismatch"
        Write-Host ""
        Write-Host "    expected  $Expected" -ForegroundColor Red
        Write-Host "    actual    $actual"   -ForegroundColor Red
        exit 1
    }
}

function Install-ManagementScript {
    $scriptPath = Join-Path $InstallDir "php-trueasync.cmd"

    # The PATH-cleanup line needs embedded single quotes inside a double-quoted cmd argument.
    # Use a double-quoted PS string with backtick-escaped $ and " to avoid all quoting issues.
    $pathClean = "powershell -ExecutionPolicy Bypass -Command `"`$p=[Environment]::GetEnvironmentVariable('Path','User'); `$p=(`$p -split ';' | Where-Object { `$_ -notlike '*php-trueasync*' }) -join ';'; [Environment]::SetEnvironmentVariable('Path',`$p,'User')`""

    $lines = [string[]]@(
        '@echo off'
        'setlocal'
        ''
        'set "INSTALL_DIR=%~dp0"'
        'set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"'
        'set "VERSION_FILE=%INSTALL_DIR%\.trueasync-version"'
        ''
        'if "%1"=="" goto :help'
        'if "%1"=="update" goto :update'
        'if "%1"=="version" goto :version'
        'if "%1"=="uninstall" goto :uninstall'
        'if "%1"=="help" goto :help'
        'if "%1"=="--help" goto :help'
        'if "%1"=="-h" goto :help'
        ''
        'echo Unknown command: %1'
        "echo Run 'php-trueasync help' for usage."
        'exit /b 1'
        ''
        ':update'
        'echo Checking for updates...'
        'if exist "%VERSION_FILE%" ('
        '    set /p CURRENT=<"%VERSION_FILE%"'
        '    echo Current version: %CURRENT%'
        ') else ('
        '    echo Current version: unknown'
        ')'
        'set "TRUEASYNC_CMD=update"'
        'powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/true-async/releases/master/installer/install.ps1 | iex"'
        'goto :eof'
        ''
        ':version'
        'if exist "%VERSION_FILE%" ('
        '    type "%VERSION_FILE%"'
        ') else ('
        '    echo unknown'
        ')'
        'goto :eof'
        ''
        ':uninstall'
        'echo Uninstalling TrueAsync PHP from %INSTALL_DIR%...'
        $pathClean
        'echo Cleaned PATH'
        'start /b cmd /c "timeout /t 1 /nobreak >nul & rd /s /q ""%INSTALL_DIR%"""'
        'echo TrueAsync PHP uninstalled.'
        'echo Restart your terminal to apply PATH changes.'
        'goto :eof'
        ''
        ':help'
        'echo TrueAsync PHP Manager'
        'echo.'
        'echo Usage: php-trueasync ^<command^>'
        'echo.'
        'echo Commands:'
        'echo   update      Check for updates and install the latest version'
        'echo   version     Show the installed version'
        'echo   uninstall   Remove TrueAsync PHP and clean up PATH'
        'echo   help        Show this help message'
        'goto :eof'
    )

    $content = $lines -join "`r`n"
    [System.IO.File]::WriteAllText($scriptPath, $content, [System.Text.Encoding]::ASCII)
}

# ── Install ───────────────────────────────────────────────────────────────────

function Do-Install {
    $platform = "windows-x64"

    Write-Info "Platform   $platform"
    Write-Host ""

    # ── Pre-flight: resolve version tag only ─────────────────────────────────

    Write-Host "  · Resolving version..." -ForegroundColor DarkGray -NoNewline

    if ($Version -eq "latest") {
        $script:Version = Get-LatestVersion
        if (-not $script:Version) { Write-Fail "Could not determine latest version" }
    }

    Write-Host "`r  " -NoNewline
    Write-Host "✓" -ForegroundColor Green -NoNewline
    Write-Host " Resolved  " -NoNewline
    Write-Host $script:Version -ForegroundColor White -NoNewline
    Write-Host "                    "  # clear trailing chars + newline

    # ── Interactive prompts ───────────────────────────────────────────────────

    Write-Host ""

    if (-not $env:INSTALL_DIR) {
        $answer = Read-Input "  Install location [$script:InstallDir]" $script:InstallDir
        $script:InstallDir = $answer
    }

    # ── Check for existing installation ──────────────────────────────────────

    $existingVer = Get-InstalledVersion

    if ($existingVer -eq $script:Version) {
        Write-Host ""
        Write-Ok "Already installed  $($script:Version)"
        Write-Host ""
        Write-Info "Use 'php-trueasync update' to check for updates"
        Write-Host ""
        return
    }

    if ($existingVer) {
        if (-not (Read-YesNo "  Found $existingVer — replace with $($script:Version)?" $true)) {
            Write-Host ""
            Write-Info "Installation cancelled"
            Write-Host ""
            return
        }
        Write-Host ""
    }

    $useDebug = $false
    if ($null -ne $DebugBuild -and $DebugBuild -ne "") {
        $useDebug = ($DebugBuild -eq "true")
    } else {
        $useDebug = Read-YesNo "  Debug build?" $false
    }

    $addToPath = $false
    if ($null -ne $SetDefault -and $SetDefault -ne "") {
        $addToPath = ($SetDefault -eq "true")
    } else {
        $addToPath = Read-YesNo "  Add to PATH?" $false
    }

    # ── Pre-install summary (rustup-style: show what WILL happen) ────────────

    Write-PreInstall -Ver $script:Version -Dir $script:InstallDir -Platform $platform -PathFlag $addToPath -Debug $useDebug

    if ($IsInteractive) {
        $proceed = Read-YesNo "  Proceed with installation?" $true
        if (-not $proceed) {
            Write-Host ""
            Write-Info "Installation cancelled"
            Write-Host ""
            return
        }
        Write-Host ""
    }

    # ── Resolve exact asset (now we know debug preference) ───────────────────

    $versionNum = $script:Version.TrimStart("v")
    $baseUrl    = "https://github.com/$Repo/releases/download/$($script:Version)"

    if ($script:PhpVersion) {
        $suffix  = if ($useDebug) { "-debug" } else { "" }
        $archive = "php-trueasync-${versionNum}-php$($script:PhpVersion)-${platform}${suffix}.zip"
    } else {
        $releaseUrl = "https://api.github.com/repos/$Repo/releases/tags/$($script:Version)"
        $release    = Invoke-RestMethod -Uri $releaseUrl -Headers @{ "User-Agent" = "TrueAsync-Installer" }
        $asset      = $release.assets | Where-Object {
            if ($useDebug) {
                $_.name -match "^php-trueasync-.*-${platform}-debug\.zip$"
            } else {
                $_.name -match "^php-trueasync-.*-${platform}\.zip$" -and $_.name -notmatch "-debug"
            }
        } | Select-Object -First 1
        if (-not $asset) {
            $buildType = if ($useDebug) { "debug" } else { "release" }
            Write-Fail "No $buildType asset found for $platform. Set PHP_VERSION to specify a PHP version."
        }
        $archive = $asset.name
    }

    # ── Numbered steps: Download → [Verify] → Install ────────────────────────

    $numSteps = if ($SkipVerify) { 2 } else { 3 }
    Set-TotalSteps $numSteps

    $tmpDir       = Join-Path $env:TEMP "php-trueasync-install-$(Get-Random)"
    $archiveUrl   = "$baseUrl/$archive"
    $checksumsUrl = "$baseUrl/sha256sums.txt"

    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

    try {
        $archivePath  = Join-Path $tmpDir $archive
        $checksumPath = Join-Path $tmpDir "sha256sums.txt"

        # Step 1: Download
        Write-Pending "Downloading"
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing `
            -Headers @{ "User-Agent" = "TrueAsync-Installer" }
        $size = Get-FormattedSize $archivePath
        Write-Done "Downloaded" $size

        # Step 2: Verify checksum
        if (-not $SkipVerify) {
            Write-Pending "Verifying checksum"
            Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumPath -UseBasicParsing

            $line = Get-Content $checksumPath | Where-Object { $_ -match [regex]::Escape($archive) }
            if ($line) {
                $expected = ($line -split '\s+')[0]
                Test-Checksum -File $archivePath -Expected $expected
                Write-Done "Checksum verified"
            } else {
                Write-Done "Checksum" "not in manifest — skipped" "Yellow"
            }
        }

        # Step 3: Install
        Write-Pending "Installing"

        if (Test-Path $script:InstallDir) {
            # Stop any PHP processes using files in this directory before deleting
            Get-Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Path -like "$($script:InstallDir)\*" } |
                Stop-Process -Force -ErrorAction SilentlyContinue
            # Retry loop — antivirus or OS may briefly hold handles after process exit
            for ($r = 0; $r -lt 5; $r++) {
                try { Remove-Item -Recurse -Force $script:InstallDir -ErrorAction Stop; break }
                catch { if ($r -eq 4) { throw } Start-Sleep -Seconds 1 }
            }
        }
        New-Item -ItemType Directory -Force -Path $script:InstallDir | Out-Null
        Expand-Archive -Path $archivePath -DestinationPath $script:InstallDir -Force
        Set-Content -Path (Join-Path $script:InstallDir $VersionFile) -Value $script:Version
        Install-ManagementScript

        Write-Done "Installed" $script:InstallDir

        # ── PATH ──────────────────────────────────────────────────────────────

        $pathStatus = "not added"
        if ($addToPath) {
            $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($curPath -notlike "*php-trueasync*") {
                [Environment]::SetEnvironmentVariable("Path", "$($script:InstallDir);$curPath", "User")
                $env:Path = "$($script:InstallDir);$env:Path"
                $pathStatus = "added"
                Write-Host ""
                Write-Warn "Restart your terminal for PATH changes to take effect"
            } else {
                $pathStatus = "already in PATH"
            }
        }

        # ── Verify installation ───────────────────────────────────────────────

        Write-Host ""

        $phpExe = Join-Path $script:InstallDir "php.exe"
        if (-not (Test-Path $phpExe)) {
            $found = Get-ChildItem -Path $script:InstallDir -Recurse -Filter "php.exe" -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if ($found) { $phpExe = $found.FullName }
        }

        if (Test-Path $phpExe) {
            Write-Host (& $phpExe -v | Select-Object -First 1) -ForegroundColor DarkGray
        }

        # ── Post-install summary ───────────────────────────────────────────────

        $summary = [ordered]@{}
        $summary["Location"] = $script:InstallDir
        $summary["Version"]  = $script:Version
        $summary["PATH"]     = $pathStatus
        $summary["Run"]      = if ($addToPath) { "php --version" } else { "$($script:InstallDir)\php.exe --version" }

        Write-Summary $summary

        Write-Host "  " -NoNewline
        Write-Host "✓" -ForegroundColor Green -NoNewline
        Write-Host "  TrueAsync PHP " -NoNewline
        Write-Host $script:Version -ForegroundColor White -NoNewline
        Write-Host " installed successfully!"
        Write-Host ""

    } finally {
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
    }
}

# ── Update ────────────────────────────────────────────────────────────────────

function Do-Update {
    $current = Get-InstalledVersion

    if (-not $current) {
        Write-Info "No existing installation found — running fresh install"
        Write-Host ""
        Do-Install
        return
    }

    Write-Info "Installed   $current"
    Write-Host "  · Checking for updates..." -ForegroundColor DarkGray -NoNewline

    $latest = Get-LatestVersion
    if (-not $latest) { Write-Fail "Could not determine latest version" }

    if ($current -eq $latest) {
        Write-Host "`r  " -NoNewline
        Write-Host "✓" -ForegroundColor Green -NoNewline
        Write-Host "  Already up to date  " -NoNewline
        Write-Host $current -ForegroundColor White
        Write-Host "               "  # clear trailing + newline
        return
    }

    Write-Host "`r  " -NoNewline
    Write-Host "↑" -ForegroundColor Cyan -NoNewline
    Write-Host "  Update available  " -NoNewline
    Write-Host $current -ForegroundColor DarkGray -NoNewline
    Write-Host "  →  " -ForegroundColor DarkGray -NoNewline
    Write-Host $latest -ForegroundColor White
    Write-Host "               "  # clear trailing + newline

    $script:Version = $latest
    Do-Install
}

# ── Uninstall ─────────────────────────────────────────────────────────────────

function Do-Uninstall {
    if (-not (Test-Path $InstallDir)) {
        Write-Warn "TrueAsync PHP is not installed at $InstallDir"
        return
    }

    $current = Get-InstalledVersion
    if ($current) { Write-Info "Version   $current" }
    Write-Info "Location  $InstallDir"
    Write-Host ""

    if ($IsInteractive) {
        $confirm = Read-YesNo "  Remove TrueAsync PHP?" $false
        if (-not $confirm) {
            Write-Info "Cancelled"
            Write-Host ""
            return
        }
        Write-Host ""
    }

    $curPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = ($curPath -split ';' | Where-Object { $_ -notlike "*php-trueasync*" }) -join ';'
    if ($newPath -ne $curPath) {
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Info "Removed from PATH"
    }

    Remove-Item -Recurse -Force $InstallDir
    Write-Host "  " -NoNewline
    Write-Host "✓" -ForegroundColor Green -NoNewline
    Write-Host "  TrueAsync PHP uninstalled"
    Write-Warn "Restart your terminal to apply PATH changes"
    Write-Host ""
}

# ── Entry point ───────────────────────────────────────────────────────────────

function Main {
    Write-Header

    switch ($Command) {
        "update"    { Do-Update }
        "uninstall" { Do-Uninstall }
        default     { Do-Install }
    }
}

Main
