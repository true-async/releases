# TrueAsync PHP

Pre-built PHP binaries with native async/coroutine support via the TrueAsync extension.

## Quick Install

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/true-async/releases/main/installer/install.ps1 | iex
```

## Manual Install

1. Go to [Releases](https://github.com/true-async/releases/releases)
2. Download the archive for your platform:
   - **Release** — for general use
   - **Debug** — for PHP/extension development (includes debug symbols and assertions)
3. Verify the SHA256 checksum from `sha256sums.txt`
4. Extract to your preferred location
5. Add the directory to your PATH

## Verify Installation

```powershell
php -v
php -m | findstr async
```

## What's Included

| Extension | Description |
|-----------|-------------|
| **async** | TrueAsync coroutine engine with libuv reactor |
| **xdebug** | Debugger and profiler |

Standard PHP extensions: curl, mbstring, openssl, pdo, pdo_mysql, pdo_pgsql, pdo_sqlite, pgsql, sockets, and more.

## Platforms

| Platform | Architecture | Build Types | Status |
|----------|-------------|-------------|--------|
| Windows  | x64         | Release, Debug | ✅ |

## Configuration

Build parameters are defined in [`build-config.json`](build-config.json):
- PHP source repository and branch
- Extensions to include
- Configure flags per platform

## Links

- [TrueAsync PHP Source](https://github.com/true-async/php-src) — PHP fork with async API
- [TrueAsync Extension](https://github.com/true-async/async) — libuv-based async implementation
- [TrueAsync Xdebug](https://github.com/true-async/xdebug) — Xdebug with async support

## License

MIT
