#!/bin/sh
# SPDX-License-Identifier: MIT
# Smoke test for -sandbox on a built qemu-system-* emulator, on Linux, macOS and Windows.
# Usage: ./scripts/smoke_test_sandbox.sh "sh /path/to/qemu-system-x86_64.com"
#
# Linux enforces the options with seccomp. macOS and Windows only implement spawn=deny
# (a Seatbelt profile, a job object) and must refuse every other setting instead of
# ignoring it. The spawn check starts a process from the monitor with `migrate "exec:..."`:
# with spawn=deny the emulator's fork() fails ("Failed to fork").

set -eu

QEMU="${1:-${QEMU_SYSTEM:-}}"
if [ -z "$QEMU" ]; then
    echo "usage: $0 <qemu-system command>" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

TIMEOUT="${SMOKE_TIMEOUT:-60}"
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

case "$(uname -s)" in
Linux) host=linux ;;
Darwin) host=macos ;;
MINGW*|MSYS*|CYGWIN*) host=windows ;;
*) echo "unsupported host: $(uname -s)" >&2; exit 2 ;;
esac

# run_monitor <monitor commands> <qemu args...>: run the commands in a paused emulator's monitor
# with no machine, output to out.txt. Returns the emulator's exit status; 124 if it hung.
run_monitor() {
    cmds=$1; shift
    printf '%s\nquit\n' "$cmds" > cmds.txt
    : > out.txt
    $QEMU -S -M none -display none -serial none -parallel none -monitor stdio "$@" \
        < cmds.txt > out.txt 2>&1 &
    pid=$!
    n=0
    while [ $n -lt "$TIMEOUT" ] && kill -0 $pid 2>/dev/null; do
        sleep 1
        n=$((n + 1))
    done
    if kill -0 $pid 2>/dev/null; then
        stop_pid $pid
        return 124
    fi
    wait $pid 2>/dev/null
}

SPAWN='migrate "exec:cat >/dev/null"'

# Without the sandbox the emulator can start a process; if it cannot, the checks
# below would prove nothing
run_monitor "$SPAWN" || fail "monitor session without a sandbox"
if grep -a -q 'Failed to fork' out.txt; then
    echo "skip - spawn checks (this host cannot fork from the monitor even without a sandbox)"
    spawn_checks=no
else
    pass "a process can be started from the monitor without a sandbox"
    spawn_checks=yes
fi

# spawn=deny works everywhere
run_monitor "$SPAWN" -sandbox on,spawn=deny || fail "-sandbox on,spawn=deny starts and quits"
if [ "$spawn_checks" = yes ]; then
    grep -a -q 'Failed to fork' out.txt || fail "-sandbox on,spawn=deny blocks starting a process"
    pass "-sandbox on,spawn=deny blocks starting a process"
else
    pass "-sandbox on,spawn=deny starts and quits"
fi

if [ "$host" = linux ]; then
    S=on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
    run_monitor "$SPAWN" -sandbox "$S" || fail "-sandbox $S starts and quits"
    if [ "$spawn_checks" = yes ]; then
        grep -a -q 'Failed to fork' out.txt || fail "-sandbox $S blocks starting a process"
    fi
    pass "-sandbox $S"

    run_monitor "info version" -sandbox on || fail "-sandbox on (default filter) starts and quits"
    pass "-sandbox on with the default filter"
else
    # Nothing here maps to seccomp's other switches: they must be refused, never ignored
    for opt in on elevateprivileges=deny resourcecontrol=deny; do
        case "$opt" in on) args="on" ;; *) args="on,spawn=deny,$opt" ;; esac
        if run_monitor "info version" -sandbox "$args"; then status=0; else status=$?; fi
        grep -a -q -E 'does nothing|not supported' out.txt \
            || fail "-sandbox $args must be refused with an error saying why"
        # a Windows process reports exit status 0 to Git Bash even when QEMU exits with 1
        if [ "$status" -eq 0 ] && [ "$host" != windows ]; then
            fail "-sandbox $args must exit with an error on this host"
        fi
        pass "-sandbox $args is refused with a clear error"
    done
fi
echo "All sandbox smoke tests passed"
