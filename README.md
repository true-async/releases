# TrueAsync PHP

Pre-built PHP binaries and Docker images with native async/coroutine support via the TrueAsync extension.

## Quick Start

### Docker (Linux)

```bash
docker pull trueasync/php-true-async:8.6
docker run --rm trueasync/php-true-async:8.6 php -v
```

Each image includes both `php` (CLI) and `php-fpm`.

Available tags:

| Tag          | Base         | Description                      |
|--------------|--------------|----------------------------------|
| `8.6`        | Ubuntu 24.04 | Full image with cli + fpm        |
| `8.6-alpine` | Alpine 3.20  | Lightweight image with cli + fpm |
| `latest`     | Ubuntu 24.04 | Alias for `8.6`                  |

### Build from Source (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh | bash
```

An interactive wizard will guide you through the build configuration: extensions, debug mode, install path, and PATH setup.

For non-interactive use (CI/scripts):

```bash
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh | \
  NO_INTERACTIVE=true EXTENSIONS=all SET_DEFAULT=true bash
```

Supported distros: Ubuntu, Debian (apt-based).

### Build from Source (macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh | bash
```

Requires [Homebrew](https://brew.sh). Supports both Apple Silicon (ARM) and Intel Macs.

For non-interactive use:

```bash
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh | \
  NO_INTERACTIVE=true EXTENSIONS=all SET_DEFAULT=true bash
```

### Windows

**Quick install (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/true-async/releases/master/installer/install.ps1 | iex
```

**Manual install:**
1. Go to [Releases](https://github.com/true-async/releases/releases)
2. Download the archive:
   - **Release** — for general use
   - **Debug** — for PHP/extension development (includes debug symbols and assertions)
3. Verify the SHA256 checksum from `sha256sums.txt`
4. Extract to your preferred location
5. Add the directory to your PATH

## Build Options

The build-from-source scripts (`build-linux.sh`, `build-macos.sh`) support these options:

| Option                | Env Variable          | Default                | Description                                   |
|-----------------------|-----------------------|------------------------|-----------------------------------------------|
| `--prefix DIR`        | `INSTALL_DIR`         | `$HOME/.php-trueasync` | Installation directory                        |
| `--set-default`       | `SET_DEFAULT=true`    | `false`                | Add to PATH as default php                    |
| `--debug`             | `DEBUG_BUILD=true`    | `false`                | Build with debug symbols                      |
| `--extensions PRESET` | `EXTENSIONS`          | `standard`             | Extension preset: `standard`, `xdebug`, `all` |
| `--no-xdebug`         | `NO_XDEBUG=true`      | `false`                | Exclude Xdebug from build                     |
| `--jobs N`            | `BUILD_JOBS`          | auto                   | Parallel make jobs                            |
| `--branch NAME`       | `PHP_BRANCH`          | from config            | Override php-src branch                       |
| `--no-interactive`    | `NO_INTERACTIVE=true` | `false`                | Skip interactive wizard                       |

By default, TrueAsync PHP is **not** added to PATH to avoid conflicts with your system PHP. Use `--set-default` to make it the default `php`.

## Management

After installation, use the `php-trueasync` command:

```bash
php-trueasync rebuild     # Rebuild from latest source
php-trueasync version     # Show installed version
php-trueasync uninstall   # Remove TrueAsync PHP
```

## Verify Installation

```bash
php -v
php -m | grep async
```

## What's Included

| Extension  | Description                                   |
|------------|-----------------------------------------------|
| **async**  | TrueAsync coroutine engine with libuv reactor |
| **xdebug** | Debugger and profiler (optional)              |

Standard PHP extensions: curl, mbstring, openssl, pdo, pdo_mysql, pdo_pgsql, pdo_sqlite, pgsql, sockets, and more.

## Platforms

| Platform  | Method             | Variants                  | Status  |
|-----------|--------------------|---------------------------|---------|
| Linux     | Docker             | Ubuntu 24.04, Alpine 3.20 | ✅       |
| Linux     | Build from source  | Ubuntu/Debian (apt)       | ✅       |
| macOS     | Build from source  | ARM + Intel (Homebrew)    | ✅       |
| Windows   | Pre-built binaries | Release, Debug (x64)      | ✅       |

## Configuration

Build parameters are defined in [`build-config.json`](build-config.json):
- PHP source repository and branch
- Extensions to include
- Configure flags per platform

## Links

- [Docker Hub](https://hub.docker.com/r/trueasync/php-true-async) — Docker images
- [TrueAsync PHP Source](https://github.com/true-async/php-src) — PHP fork with async API
- [TrueAsync Extension](https://github.com/true-async/async) — libuv-based async implementation
- [TrueAsync Xdebug](https://github.com/true-async/xdebug) — Xdebug with async support

## License

MIT
