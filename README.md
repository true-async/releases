# TrueAsync PHP

Pre-built PHP binaries and Docker images with native async/coroutine support via the TrueAsync extension.

## Quick Start

### Docker (Linux)

```bash
docker pull trueasync/php-true-async:latest
docker run --rm trueasync/php-true-async:latest php -v
```

Each image includes both `php` (CLI) and `php-fpm`. All images are **multi-arch**: `linux/amd64` and `linux/arm64` — Docker picks the right variant automatically.

Available tags:

| Tag                          | Base         | Arch           | Description                           |
|------------------------------|--------------|----------------|---------------------------------------|
| `latest`                     | Ubuntu 24.04 | amd64 + arm64  | Latest stable, cli + fpm              |
| `latest-alpine`              | Alpine edge  | amd64 + arm64  | Lightweight, cli + fpm                |
| `latest-frankenphp`          | Ubuntu 24.04 | amd64 + arm64  | FrankenPHP — Caddy + async PHP worker |
| `latest-debug`               | Ubuntu 24.04 | amd64          | Debug build with symbols              |
| `{version}-php{ver}`         | Ubuntu 24.04 | amd64 + arm64  | Pinned release, e.g. `0.7.0-php8.4`  |
| `{version}-php{ver}-alpine`  | Alpine edge  | amd64 + arm64  | Pinned alpine release                 |
| `{version}-php{ver}-frankenphp` | Ubuntu 24.04 | amd64 + arm64 | Pinned FrankenPHP release            |

### TrueAsync Server

[TrueAsync Server](https://github.com/true-async/server) is a native PHP extension that runs a high-performance HTTP server **directly inside PHP** — no reverse proxy, no external daemon, no separate process.

A single `$server->start()` call serves HTTP/1.1, HTTP/2, and HTTP/3 (QUIC) over the same port via ALPN negotiation, driven by the TrueAsync event loop. WebSocket, SSE, and gRPC are planned.

```php
use TrueAsync\HttpServer;
use TrueAsync\HttpServerConfig;

$server = new HttpServer(
    (new HttpServerConfig())
        ->addListener('0.0.0.0', 8080)
        ->setWorkers(4)
);

$server->addHttpHandler(function ($request, $response) {
    $response->setStatusCode(200)->setBody('Hello, World!');
});

$server->start();
```

See [true-async/server](https://github.com/true-async/server) for installation and full documentation.

### Build from Source (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh | bash
```

An interactive wizard will guide you through the build configuration: extensions, FrankenPHP, debug mode, install path, and PATH setup.

For non-interactive use (CI/scripts):

```bash
# Standard build
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh | \
  NO_INTERACTIVE=true EXTENSIONS=all SET_DEFAULT=true bash

# With FrankenPHP
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-linux.sh | \
  NO_INTERACTIVE=true EXTENSIONS=all BUILD_FRANKENPHP=true SET_DEFAULT=true bash
```

Supported distros: Ubuntu, Debian (apt-based).

### Build from Source (macOS)

```bash
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh | bash
```

Requires [Homebrew](https://brew.sh). Supports both Apple Silicon (ARM) and Intel Macs.

For non-interactive use:

```bash
# Standard build
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh | \
  NO_INTERACTIVE=true EXTENSIONS=all SET_DEFAULT=true bash

# With FrankenPHP
curl -fsSL https://raw.githubusercontent.com/true-async/releases/master/installer/build-macos.sh | \
  NO_INTERACTIVE=true EXTENSIONS=all BUILD_FRANKENPHP=true SET_DEFAULT=true bash
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

| Option                | Env Variable             | Default                | Description                                          |
|-----------------------|--------------------------|------------------------|------------------------------------------------------|
| `--prefix DIR`        | `INSTALL_DIR`            | `$HOME/.php-trueasync` | Installation directory                               |
| `--set-default`       | `SET_DEFAULT=true`       | `false`                | Add to PATH as default php                           |
| `--debug`             | `DEBUG_BUILD=true`       | `false`                | Build with debug symbols                             |
| `--extensions PRESET` | `EXTENSIONS`             | `standard`             | Extension preset: `standard`, `xdebug`, `all` (see below) |
| `--no-xdebug`         | `NO_XDEBUG=true`         | `false`                | Exclude Xdebug from build                            |
| `--frankenphp`        | `BUILD_FRANKENPHP=true`  | `false`                | Build FrankenPHP binary (Caddy-based async server)   |
| `--no-latest-curl`    | `BUILD_LATEST_CURL=false`| `true`                 | Skip building libcurl 8.12.0 (async uploads fallback)|
| `--jobs N`            | `BUILD_JOBS`             | auto                   | Parallel make jobs                                   |
| `--branch NAME`       | `PHP_BRANCH`             | from config            | Override php-src branch                              |
| `--no-interactive`    | `NO_INTERACTIVE=true`    | `false`                | Skip interactive wizard                              |

**Extension presets** (`--extensions`):

| Preset     | Xdebug | Description                        |
|------------|--------|------------------------------------|
| `standard` | No     | async + core PHP extensions        |
| `xdebug`   | Yes    | standard + Xdebug debugger         |
| `all`       | Yes    | everything (same as `xdebug`)      |

FrankenPHP is opt-in via `--frankenphp` / `BUILD_FRANKENPHP=true` regardless of the preset. Requires Go 1.26+ (installed automatically if not found).

By default, the installer builds **libcurl 8.12.0** from source. This is required for fully async file uploads — libcurl >= 8.11.1 fixes PAUSE/unpause bugs ([curl#15627](https://github.com/curl/curl/pull/15627)) that caused intermittent timeouts. Use `--no-latest-curl` to skip this and use the system libcurl (async uploads will fall back to synchronous reads).

TrueAsync PHP is **not** added to PATH by default to avoid conflicts with your system PHP. Use `--set-default` to make it the default `php`.

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
| Linux     | Docker (amd64)     | Ubuntu 24.04, Alpine edge, FrankenPHP | ✅       |
| Linux     | Docker (arm64)     | Ubuntu 24.04, Alpine edge, FrankenPHP | ✅       |
| Linux     | Build from source  | Ubuntu/Debian (apt)       | ✅       |
| macOS     | Build from source  | ARM + Intel (Homebrew)    | ✅       |
| Windows   | Pre-built binaries | Release, Debug (x64)      | ✅       |

## Configuration

Build parameters are defined in [`build-config.json`](build-config.json):
- PHP source repository and branch
- Extensions to include
- Configure flags per platform

## Links

- [TrueAsync Server](https://github.com/true-async/server) — native HTTP/1.1, HTTP/2, HTTP/3 server as a PHP extension
- [Docker Hub](https://hub.docker.com/r/trueasync/php-true-async) — Docker images
- [TrueAsync PHP Source](https://github.com/true-async/php-src) — PHP fork with async API
- [TrueAsync Extension](https://github.com/true-async/async) — libuv-based async implementation
- [TrueAsync Xdebug](https://github.com/true-async/xdebug) — Xdebug with async support
- [TrueAsync FrankenPHP](https://github.com/true-async/frankenphp) — FrankenPHP fork with async worker support

## License

MIT
