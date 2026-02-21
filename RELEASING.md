# Release Guide

## Tag naming convention

Each repository in the TrueAsync ecosystem uses its own tag format. Tags must be created **in all repositories** before triggering a release in this repo.

### `true-async/releases` (this repo)

Triggers CI/CD. Tags here drive the entire release pipeline.

| Type | Format | Example |
|---|---|---|
| Stable release | `vX.Y.Z` | `v1.0.0` |
| Pre-release (beta) | `vX.Y.Z-beta.N` | `v0.6.0-beta.1` |
| Pre-release (RC) | `vX.Y.Z-rc.N` | `v1.0.0-rc.1` |
| Pre-release (alpha) | `vX.Y.Z-alpha.N` | `v0.6.0-alpha.1` |

The version number (`X.Y.Z`) is the **product version**, independent of the PHP version.
The PHP version is defined in `build-config.json` and embedded in artifact names automatically.

### `true-async/php-src`

Follows the same convention as the official `php/php-src` repository, with a `-trueasync` suffix to distinguish from upstream tags.

| Type | Format | Example |
|---|---|---|
| Stable release | `php-X.Y.Z-trueasync` | `php-8.6.0-trueasync` |
| Pre-release (beta) | `php-X.Y.Z-trueasync-beta.N` | `php-8.6.0-trueasync-beta.1` |
| Pre-release (RC) | `php-X.Y.Z-trueasync-rc.N` | `php-8.6.0-trueasync-rc.1` |

Here `X.Y.Z` is the **PHP version** (e.g. `8.6.0`), not the product version.
This makes it easy to see at a glance which PHP version the tag is based on and clearly distinguishes it from upstream PHP tags.

### `true-async/php-async`

Has its own independent version, not tied to the PHP version.

| Type | Format | Example |
|---|---|---|
| Stable release | `vX.Y.Z` | `v0.6.0` |
| Pre-release (beta) | `vX.Y.Z-beta.N` | `v0.6.0-beta.1` |
| Pre-release (RC) | `vX.Y.Z-rc.N` | `v0.6.0-rc.1` |
| Pre-release (alpha) | `vX.Y.Z-alpha.N` | `v0.6.0-alpha.1` |

---

## Tagging order

Always tag source repositories **before** triggering the release in this repo:

1. Tag `true-async/php-src`
2. Tag `true-async/php-async`
3. Tag `true-async/xdebug`
4. Update `build-config.json` branch fields to point to the new tags
5. Tag `true-async/releases` → CI/CD starts

---

## Before any release

### 1. Update `build-config.json` if needed

Check that the branches point to the correct commits:

```json
{
  "php_version": "8.6",
  "php_is_latest": true,
  "php_src": { "branch": "true-async-stable" },
  "extensions": {
    "async":  { "branch": "main" },
    "xdebug": { "branch": "true-async-86" }
  }
}
```

- `php_version` — PHP version embedded in all artifact names and Docker tags
- `php_is_latest` — set to `true` if this PHP version should receive the `latest` Docker tag; set to `false` for older PHP versions when a newer one is released
- Branch fields — must point to the stable/release-ready state

Commit and push any changes to `build-config.json` before tagging.

### 2. Run a test build (optional but recommended)

Trigger the workflows manually without publishing artifacts:

1. Go to **Actions → Build & Push Docker Images** → **Run workflow**
   - Leave `test_only` checked (default)
2. Go to **Actions → Build & Release TrueAsync PHP** → **Run workflow**
   - Leave `test_only` checked (default)

Make sure both complete successfully before tagging.

---

## Pre-release

Use pre-releases to test before a stable release. Pre-releases:
- Create a GitHub Release marked as **Pre-release**
- Push versioned Docker tags only (no `latest`, no `latest-php*`)
- Publish Windows artifacts to the GitHub Release

```bash
git tag v0.6.0-beta.1
git push origin v0.6.0-beta.1
```

**Resulting artifacts:**

| Artifact | Value |
|---|---|
| Windows ZIP | `php-trueasync-0.6.0-beta.1-php8.6-windows-x64.zip` |
| Windows ZIP (debug) | `php-trueasync-0.6.0-beta.1-php8.6-windows-x64-debug.zip` |
| Docker (debian) | `trueasync/php-true-async:0.6.0-beta.1-php8.6` |
| Docker (alpine) | `trueasync/php-true-async:0.6.0-beta.1-php8.6-alpine` |
| Docker (debug) | `trueasync/php-true-async:0.6.0-beta.1-php8.6-debug` |
| GitHub Release | Pre-release, not shown as "latest" |

If issues are found, tag the next iteration:

```bash
git tag v0.6.0-beta.2
git push origin v0.6.0-beta.2
```

---

## Stable release

Once testing is complete:

```bash
git tag v0.6.0
git push origin v0.6.0
```

**Resulting artifacts:**

| Artifact | Value |
|---|---|
| Windows ZIP | `php-trueasync-0.6.0-php8.6-windows-x64.zip` |
| Windows ZIP (debug) | `php-trueasync-0.6.0-php8.6-windows-x64-debug.zip` |
| Docker (debian) | `trueasync/php-true-async:0.6.0-php8.6` |
| Docker (debian) | `trueasync/php-true-async:latest-php8.6` |
| Docker (debian) | `trueasync/php-true-async:latest` |
| Docker (alpine) | `trueasync/php-true-async:0.6.0-php8.6-alpine` |
| Docker (alpine) | `trueasync/php-true-async:latest-php8.6-alpine` |
| Docker (alpine) | `trueasync/php-true-async:latest-alpine` |
| Docker (debug) | `trueasync/php-true-async:latest-php8.6-debug` |
| Docker (debug) | `trueasync/php-true-async:latest-debug` |
| GitHub Release | Stable, shown as latest release |

---

## Adding a new PHP version

When PHP 8.7 (or later) is ready:

1. Update `build-config.json`:
   ```json
   {
     "php_version": "8.7",
     "php_is_latest": true
   }
   ```
2. For the old PHP version (8.6), create a separate branch of this repo (e.g. `php-8.6`) and set `php_is_latest: false` there — this allows continued releases for 8.6 without affecting `latest` tags.
3. Tag and release as usual on the new branch.

---

## Monitoring

After pushing a tag, monitor progress at:

```
https://github.com/true-async/releases/actions
```

Two workflows run in parallel:
- **Build & Release TrueAsync PHP** — Windows builds + GitHub Release
- **Build & Push Docker Images** — Docker images (debian, alpine, debug)

Both must succeed for the release to be complete.
