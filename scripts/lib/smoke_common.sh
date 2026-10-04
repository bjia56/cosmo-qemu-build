# shellcheck shell=sh
# SPDX-License-Identifier: MIT
# Helpers shared by the smoke tests. Sourced by scripts/smoke_test_*.sh (POSIX sh, also Git Bash).

case "$(uname -s)" in
Linux) host=linux ;;
Darwin) host=macos ;;
MINGW*|MSYS*|CYGWIN*) host=windows ;;
*) echo "unsupported host: $(uname -s)" >&2; exit 2 ;;
esac

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; [ -f out.txt ] && tail -n 20 out.txt >&2; exit 1; }

# stop_pid <pid>: end a background emulator. The reaping only happens once it is gone: a native
# Windows process can ignore kill, and waiting for it would hang the whole test.
stop_pid() {
    kill "$1" 2>/dev/null || true
    sleep 1
    if kill -0 "$1" 2>/dev/null; then
        kill -9 "$1" 2>/dev/null || true
    else
        wait "$1" 2>/dev/null || true
    fi
}
