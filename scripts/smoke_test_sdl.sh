#!/bin/sh
# SPDX-License-Identifier: MIT
# Opens the guest's display in an SDL window on a virtual X server and checks the
# window exists. The emulator loads the host's SDL2 at run time, so this needs
# libSDL2 (Ubuntu: libsdl2-2.0-0) plus Xvfb and xdotool; without them it skips.
#
# Usage: ./scripts/smoke_test_sdl.sh "sh /path/to/qemu-system-x86_64.com"

set -eu

QEMU="${1:-${QEMU_SYSTEM:-}}"
if [ -z "$QEMU" ]; then
    echo "usage: $0 <qemu-system-x86_64 command>" >&2
    exit 2
fi
for tool in Xvfb xdotool; do
    command -v "$tool" >/dev/null 2>&1 || { echo "skip - $tool not installed"; exit 0; }
done

DISPLAY_NUM=$((90 + $$ % 9))
export DISPLAY=":${DISPLAY_NUM}"
Xvfb "$DISPLAY" -screen 0 1024x768x24 >/dev/null 2>&1 &
xpid=$!
sleep 2
trap 'kill $qpid 2>/dev/null || true; kill $xpid 2>/dev/null || true' EXIT

$QEMU -display sdl -m 64 -net none -monitor none -serial none > sdl-out.txt 2>&1 &
qpid=$!

n=0
while [ $n -lt 30 ]; do
    if xdotool search --name QEMU 2>/dev/null | grep -q .; then
        echo "ok   - SDL window opened (host SDL2 loaded at run time)"
        exit 0
    fi
    if grep -a -q "cannot load the SDL2 library" sdl-out.txt 2>/dev/null; then
        echo "skip - the host has no SDL2 library"
        exit 0
    fi
    kill -0 $qpid 2>/dev/null || break
    sleep 1
    n=$((n + 1))
done
echo "FAIL - no SDL window" >&2
cat sdl-out.txt >&2
exit 1
