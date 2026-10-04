#!/bin/sh
# SPDX-License-Identifier: MIT
# Checks that -display sdl starts on Linux, macOS and Windows (Git Bash): SDL2 is loaded (the embedded
# library on Windows and macOS, the host's on Linux), nothing crashes, the guest runs (monitor on
# stdio) and the emulator is still alive a few seconds later. Linux and Windows also look for the
# window, which needs Xvfb and xdotool on Linux (the test is skipped without them or without libSDL2).
# Usage: ./scripts/smoke_test_sdl.sh "sh /path/to/qemu-system-x86_64.com"

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/lib/smoke_common.sh"

QEMU="${1:-${QEMU_SYSTEM:-}}"
if [ -z "$QEMU" ]; then
    echo "usage: $0 <qemu-system-x86_64 command>" >&2
    exit 2
fi

xpid=
qpid=
cleanup() {
    [ -n "$qpid" ] && stop_pid "$qpid"
    [ -n "$xpid" ] && kill "$xpid" 2>/dev/null || true
}
trap cleanup EXIT

if [ "$host" = linux ]; then
    for tool in Xvfb xdotool; do
        command -v "$tool" >/dev/null 2>&1 || { echo "skip - $tool not installed"; exit 0; }
    done
    DISPLAY_NUM=$((90 + $$ % 9))
    export DISPLAY=":${DISPLAY_NUM}"
    Xvfb "$DISPLAY" -screen 0 1024x768x24 >/dev/null 2>&1 &
    xpid=$!
    sleep 2
fi

window_open() {
    case "$host" in
    linux) xdotool search --name QEMU 2>/dev/null | grep -q . ;;
    windows)
        powershell.exe -NoProfile -Command \
            "if (Get-Process | Where-Object { \$_.MainWindowTitle -like '*QEMU*' }) { exit 0 } else { exit 1 }" \
            >/dev/null 2>&1
        ;;
    *) return 0 ;; # macOS: no reliable way to look without accessibility permission
    esac
}

# diagnose <reason>: fail, with what is left of the emulator
diagnose() {
    if [ "$host" = windows ]; then
        echo "-- windows processes:" >&2
        tasklist 2>/dev/null | grep -i qemu >&2 || echo "(no qemu process)" >&2
        kill -0 "$qpid" 2>/dev/null && echo "(kill -0 says it is alive)" >&2
    fi
    echo "-- window: $(window_open && echo yes || echo no)" >&2
    echo "-- output (last 80 lines):" >&2
    tail -n 80 out.txt >&2
    fail "$1"
}

crashed() { grep -a -q -E "SIGSEGV|SIGILL|SIGABRT|Terminating on|^error:|Uncaught" out.txt; }

# The monitor reads its commands from a file; at the end of the file QEMU keeps running
echo "info status" > cmds.txt
$QEMU -display sdl -m 64 -net none -serial none -parallel none -monitor stdio \
    < cmds.txt > out.txt 2>&1 &
qpid=$!

n=0
until grep -a -q "VM status: running" out.txt; do
    if [ "$host" = linux ] && grep -a -q "cannot load the SDL2 library" out.txt; then
        echo "skip - the host has no SDL2 library"
        exit 0
    fi
    crashed && diagnose "SDL (crashed)"
    kill -0 "$qpid" 2>/dev/null || diagnose "SDL (the emulator exited)"
    n=$((n + 1))
    [ $n -lt 30 ] || diagnose "SDL (the guest did not report running)"
    sleep 1
done
pass "SDL: the emulator runs"

if [ "$host" != macos ]; then
    n=0
    until window_open; do
        n=$((n + 1))
        [ $n -lt 30 ] || diagnose "SDL (no window titled QEMU)"
        kill -0 "$qpid" 2>/dev/null || diagnose "SDL (the emulator exited)"
        sleep 1
    done
    pass "SDL: the window opened"
fi

# a late crash shows up by now
sleep 5
kill -0 "$qpid" 2>/dev/null || diagnose "SDL (the emulator exited after startup)"
crashed && diagnose "SDL (crashed after startup)"
pass "SDL: still running after 5 seconds"
