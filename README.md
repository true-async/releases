# TrueAsync PHP

Pre-built PHP binaries and Docker images with native async/coroutine support via the TrueAsync extension.

## Docker (Linux)

```bash
docker pull trueasync/php-true-async:8.6
docker run --rm trueasync/php-true-async:8.6 php -v
```

Each image includes both `php` (CLI) and `php-fpm`.

Available tags:

| Tag | Base | Description |
|-----|------|-------------|
| `8.6` | Ubuntu 24.04 | Full image with cli + fpm |
| `8.6-alpine` | Alpine 3.20 | Lightweight image with cli + fpm |
| `latest` | Ubuntu 24.04 | Alias for `8.6` |

## Windows

**Quick install (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/true-async/releases/main/installer/install.ps1 | iex
```

**Manual install:**
1. Go to [Releases](https://github.com/true-async/releases/releases)
2. Download the archive:
   - **Release** — for general use
   - **Debug** — for PHP/extension development (includes debug symbols and assertions)
3. Verify the SHA256 checksum from `sha256sums.txt`
4. Extract to your preferred location
5. Add the directory to your PATH

## Verify Installation

```bash
php -v
php -m | grep async
```

## What's Included

| Extension | Description |
|-----------|-------------|
| **async** | TrueAsync coroutine engine with libuv reactor |
| **xdebug** | Debugger and profiler |

Standard PHP extensions: curl, mbstring, openssl, pdo, pdo_mysql, pdo_pgsql, pdo_sqlite, pgsql, sockets, and more.

## Platforms

| Platform | Distribution | Variants | Status |
|----------|-------------|----------|--------|
| Linux    | Docker      | Ubuntu 24.04, Alpine 3.20 | ✅ |
| Windows  | x64         | Release, Debug | ✅ |

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
