#!/usr/bin/env bash
# Drives the installer wizard through a matrix of choice scenarios.
#
# Each scenario feeds pre-canned keystrokes to wizard-harness.sh through a PTY
# (so the installer believes it is interactive) running under the system
# /bin/bash 3.2, then asserts the resulting log:
#   - which build steps got dispatched (STEP:...)
#   - the final resolved config (CONFIG ...)
#   - that no bash-4-only syntax fired ("bad substitution")
#
# Exit code is non-zero if any scenario fails.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
HARNESS="${here}/wizard-harness.sh"
[[ -f "$HARNESS" ]] || { echo "harness not found: $HARNESS" >&2; exit 1; }

# Allocate a PTY for the child so `[[ -t 0 ]]` is true; forward our piped
# keystrokes into it. A 30s alarm guards against a hang if input runs short.
PTY_PY='
import pty, sys, signal
signal.alarm(30)
try:
    rc = pty.spawn(["/bin/bash", sys.argv[1]])
except Exception as e:
    sys.stderr.write("PTY-ERROR: %s\n" % e)
    rc = 99
sys.exit(rc if isinstance(rc, int) else 0)
'

pass=0
fail=0

# run_case <name> <keystrokes> <expect>...
#   expect: substring that MUST appear; prefix with '!' for MUST-NOT appear.
run_case() {
    local name="$1" keys="$2"
    shift 2
    local expects=("$@")

    local log
    log="$(mktemp)"
    printf '%b' "$keys" | python3 -c "$PTY_PY" "$HARNESS" > "$log" 2>&1 || true

    local ok=1 detail="" pat
    if grep -qi 'bad substitution' "$log"; then
        ok=0; detail+=$'\n    - hit "bad substitution" (bash-4 syntax on bash 3.2)'
    fi
    for pat in "${expects[@]}"; do
        if [[ "$pat" == '!'* ]]; then
            if grep -qF -- "${pat:1}" "$log"; then
                ok=0; detail+=$'\n    - unexpected: '"${pat:1}"
            fi
        else
            if ! grep -qF -- "$pat" "$log"; then
                ok=0; detail+=$'\n    - missing:    '"$pat"
            fi
        fi
    done

    if (( ok )); then
        printf '  [PASS] %s\n' "$name"
        pass=$((pass + 1))
    else
        printf '  [FAIL] %s%s\n' "$name" "$detail"
        echo   "  ----- captured log -----"
        sed 's/^/  | /' "$log"
        echo   "  ------------------------"
        fail=$((fail + 1))
    fi
    rm -f "$log"
}

echo "System bash: $(/bin/bash --version | head -1)"
echo "Running wizard choice matrix..."
echo

run_case "ext1: Standard (no Xdebug, no FrankenPHP)" '1\n\n\n\n\n\n' \
    'CONFIG EXTENSIONS=standard' 'NO_XDEBUG=true' 'BUILD_FRANKENPHP=false' \
    'STEP:frankenphp:SKIP' '!STEP:xdebug'

run_case "ext2: DEFAULT via Enter = Standard+Xdebug  [set -e regression]" '\n\n\n\n\n\n' \
    'CONFIG EXTENSIONS=standard' 'NO_XDEBUG=false' 'STEP:xdebug' 'STEP:frankenphp:SKIP'

run_case "ext3: Standard+FrankenPHP" '3\n\n\n\n\n\n' \
    'NO_XDEBUG=true' 'BUILD_FRANKENPHP=true' 'STEP:frankenphp:RAN' '!STEP:xdebug'

run_case "ext4: All (Xdebug + FrankenPHP)" '4\n\n\n\n\n\n' \
    'CONFIG EXTENSIONS=all' 'NO_XDEBUG=false' 'BUILD_FRANKENPHP=true' \
    'STEP:xdebug' 'STEP:frankenphp:RAN'

run_case "ext5 Custom: Xdebug=Y Franken=y  [uppercase input / bug #2]" '5\nY\ny\n\n\n\n\n\n' \
    'NO_XDEBUG=false' 'BUILD_FRANKENPHP=true' 'STEP:xdebug' 'STEP:frankenphp:RAN'

run_case "ext5 Custom: Xdebug=n Franken=N  [uppercase input / bug #2]" '5\nn\nN\n\n\n\n\n\n' \
    'NO_XDEBUG=true' 'BUILD_FRANKENPHP=false' 'STEP:frankenphp:SKIP' '!STEP:xdebug'

run_case "ext1 + HTTP3=Y, debug=y, set-default=y" '1\nY\ny\n\ny\n\n' \
    'BUILD_HTTP3=true' 'DEBUG_BUILD=true' 'SET_DEFAULT=true'

echo
echo "===== RESULT: ${pass} passed, ${fail} failed ====="
(( fail == 0 ))
