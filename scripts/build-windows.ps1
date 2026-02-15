#Requires -Version 5.1
<#
.SYNOPSIS
    TrueAsync PHP Windows build script.
.DESCRIPTION
    Builds PHP with TrueAsync extension on Windows using MSVC.
    Requires Visual Studio 2022 and php-sdk-binary-tools.
.PARAMETER ConfigFile
    Path to build-config.json
.PARAMETER Prefix
    Installation prefix (default: C:\php-trueasync)
.PARAMETER SdkPath
    Path to php-sdk-binary-tools (default: C:\php-sdk)
.PARAMETER DepsPath
    Path to PHP build dependencies (default: C:\php-deps)
#>
param(
    [string]$ConfigFile = "$PSScriptRoot\..\build-config.json",
    [string]$Prefix = "C:\php-trueasync",
    [string]$SdkPath = "C:\php-sdk",
    [string]$DepsPath = "C:\php-deps",
    [string]$SrcDir = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== TrueAsync PHP Windows Build ===" -ForegroundColor Cyan
Write-Host "Config:  $ConfigFile"
Write-Host "Prefix:  $Prefix"
Write-Host "SDK:     $SdkPath"
Write-Host "Deps:    $DepsPath"

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Config file not found: $ConfigFile"
    exit 1
}

$config = Get-Content $ConfigFile | ConvertFrom-Json

# --- Setup PHP SDK ---
if (-not (Test-Path $SdkPath)) {
    Write-Host "=== Cloning php-sdk-binary-tools ===" -ForegroundColor Yellow
    git clone --depth=1 https://github.com/php/php-sdk-binary-tools.git $SdkPath
}

# --- Setup libuv via vcpkg ---
Write-Host "=== Setting up libuv ===" -ForegroundColor Yellow
$vcpkgRoot = $env:VCPKG_INSTALLATION_ROOT
if (-not $vcpkgRoot) {
    $vcpkgRoot = "C:\vcpkg"
}

if (-not (Test-Path "$vcpkgRoot\installed\x64-windows\include\uv.h")) {
    & "$vcpkgRoot\vcpkg.exe" install libuv:x64-windows
}

New-Item -ItemType Directory -Force -Path "$DepsPath\include", "$DepsPath\lib" | Out-Null

# Copy headers
Copy-Item -Recurse -Force "$vcpkgRoot\installed\x64-windows\include\*" "$DepsPath\include\"

# Ensure libuv subdirectory structure for config.w32
if (-not (Test-Path "$DepsPath\include\libuv")) {
    New-Item -ItemType Directory -Force -Path "$DepsPath\include\libuv" | Out-Null
    Copy-Item "$DepsPath\include\uv.h" "$DepsPath\include\libuv\"
    if (Test-Path "$DepsPath\include\uv") {
        Copy-Item -Recurse -Force "$DepsPath\include\uv" "$DepsPath\include\libuv\"
    }
}

# Copy library
Copy-Item -Force "$vcpkgRoot\installed\x64-windows\lib\uv.lib" "$DepsPath\lib\libuv.lib"
Copy-Item -Force "$vcpkgRoot\installed\x64-windows\bin\*.dll" "$DepsPath\lib\" -ErrorAction SilentlyContinue

# --- Clone sources ---
if (-not $SrcDir) {
    $SrcDir = Join-Path $env:TEMP "php-trueasync-build"
    if (Test-Path $SrcDir) { Remove-Item -Recurse -Force $SrcDir }

    Write-Host "=== Cloning php-src ===" -ForegroundColor Yellow
    $phpRepo = $config.php_src.repo
    $phpBranch = $config.php_src.branch
    git clone --depth=1 --branch $phpBranch "https://github.com/$phpRepo.git" $SrcDir

    foreach ($extName in $config.extensions.PSObject.Properties.Name) {
        $ext = $config.extensions.$extName
        Write-Host "=== Cloning $($ext.repo) ===" -ForegroundColor Yellow
        git clone --depth=1 --branch $ext.branch "https://github.com/$($ext.repo).git" "$SrcDir\$($ext.path)"
    }
}

# --- Build ---
Write-Host "=== Building PHP ===" -ForegroundColor Yellow

$buildScript = @"
call "$SdkPath\phpsdk-vs17-x64.bat"
cd /d "$SrcDir"
call buildconf.bat
call configure.bat --enable-zts --enable-async --enable-xdebug --enable-phpdbg --enable-mbstring --enable-sockets --enable-pdo --enable-ftp --enable-shmop --with-curl --with-sqlite3 --with-pdo-sqlite --with-pdo-mysql --with-openssl --enable-debug-pack --with-php-build=$DepsPath --with-prefix=$Prefix
nmake
nmake install
"@

$batchFile = Join-Path $env:TEMP "php-build.bat"
$buildScript | Set-Content -Path $batchFile -Encoding ASCII
& cmd.exe /c $batchFile

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed with exit code $LASTEXITCODE"
    exit 1
}

# --- Verify ---
Write-Host "=== Verifying build ===" -ForegroundColor Yellow
& "$Prefix\php.exe" -v
& "$Prefix\php.exe" -m

Write-Host "=== Build complete ===" -ForegroundColor Green
Write-Host "Installed to: $Prefix"
