#!/usr/bin/env bash
# Test harness for the macOS installer's interactive wizard.
#
# Loads the real installer's functions, replaces every side-effecting build step
# with a logging stub, then runs the *real* main() — so the whole flow is
# exercised (tty detection -> wizard prompts -> choice mapping -> step dispatch)
# without doing any real work (no brew / clone / configure / make).
#
# Meant to be launched under the macOS system /bin/bash (3.2.57) via a PTY so
# that `[[ -t 0 ]]` is true and the wizard actually runs.

set -uo pipefail

# Never re-download/relaunch; force the interactive path even though CI sets CI=1
export __TRUEASYNC_RELAUNCHED=1
unset CI
export NO_INTERACTIVE=false

here="$(cd "$(dirname "$0")" && pwd)"
installer="${here}/../build-macos.sh"

# Load the installer's functions without running its bottom `main "$@"` call.
src="$(mktemp)"
sed 's/^main "\$@"$/: # main call stripped; harness invokes main itself/' "$installer" > "$src"
# shellcheck disable=SC1090
source "$src"

# ── Stubs: log instead of act ────────────────────────────────────────────────
check_system()         { echo "STEP:check_system"; }
read_config()          { echo "STEP:read_config"; }
install_dependencies() { echo "STEP:install_dependencies"; }
build_libcurl()        { echo "STEP:build_libcurl"; }
clone_sources()        { echo "STEP:clone_sources"; }
configure_php()        { echo "STEP:configure_php"; }
build_php()            { echo "STEP:build_php"; }
install_php()          { echo "STEP:install_php"; }
build_xdebug()         { echo "STEP:xdebug"; }
build_server()         { echo "STEP:server"; }
build_frankenphp() {
    # Mirror the real function's own guard so dispatch is testable
    if [[ "$BUILD_FRANKENPHP" == "true" ]]; then
        echo "STEP:frankenphp:RAN"
    else
        echo "STEP:frankenphp:SKIP"
    fi
}
setup_config()         { echo "STEP:setup_config"; }
setup_path()           { echo "STEP:setup_path"; }
verify_installation()  { echo "STEP:verify_installation"; }
show_final_message() {
    echo "CONFIG EXTENSIONS=${EXTENSIONS} NO_XDEBUG=${NO_XDEBUG} BUILD_FRANKENPHP=${BUILD_FRANKENPHP} BUILD_HTTP3=${BUILD_HTTP3} DEBUG_BUILD=${DEBUG_BUILD} SET_DEFAULT=${SET_DEFAULT}"
}

# Point INSTALL_DIR at a fresh, empty path so the "existing install" branch is skipped
INSTALL_DIR="$(mktemp -d)/php-trueasync"

main "$@"
