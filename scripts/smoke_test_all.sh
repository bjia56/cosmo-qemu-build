#!/bin/sh
# SPDX-License-Identifier: MIT
# Runs every smoke test against built executables on the machine you are on (Linux, macOS or
# Windows under Git Bash), including the second pass of the system emulator tests with -sandbox.
# Usage: ./scripts/smoke_test_all.sh [directory with qemu-img.com and qemu-system-*.com (default: ./out)] [stage...]
# Stages: img, system, sandbox, system-sandbox (default: all of them). CI runs each as its own step.
#
# The aarch64 halves on an x86_64 Linux machine are tested by smoke_test_aarch64.sh instead.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR="$(cd "${1:-${SCRIPT_DIR}/../out}" && pwd)"
[ $# -gt 0 ] && shift
stages="${*:-img system sandbox system-sandbox}"

case "$(uname -s)" in
Linux) host=linux ;;
Darwin) host=macos ;;
MINGW*|MSYS*|CYGWIN*) host=windows ;;
*) echo "unsupported host: $(uname -s)" >&2; exit 2 ;;
esac

# Windows runs executables that end in .exe; elsewhere the APE files are started through sh,
# which also covers a download that lost its executable bit
if [ "$host" = windows ]; then
    # once: a copy still running from an earlier stage keeps its file locked
    for f in "$DIR"/*.com; do [ -f "${f%.com}.exe" ] || cp "$f" "${f%.com}.exe"; done
    cmd() { echo "$DIR/$1.exe"; }
    sandbox=on,spawn=deny
else
    cmd() { echo "sh $DIR/$1.com"; }
    sandbox=on,spawn=deny
    # seccomp can enforce every switch
    [ "$host" = linux ] && sandbox=on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
fi

failed=""
# step <name> <command...>: a failing test script does not stop the others
step() {
    name=$1; shift
    echo ""
    echo "== $name"
    if ! "$@"; then
        echo "FAILED: $name" >&2
        failed="${failed}
  $name"
    fi
}

guests=""
for guest in x86_64 aarch64; do
    [ -f "$DIR/qemu-system-${guest}.com" ] && guests="$guests $guest"
done
[ -n "$guests" ] || { echo "no qemu-system-*.com in $DIR" >&2; exit 2; }
set -- $guests
first=$1

for stage in $stages; do
    case "$stage" in
    img)
        step "qemu-img" "${SCRIPT_DIR}/smoke_test.sh" "$(cmd qemu-img)"
        ;;
    system)
        for guest in $guests; do
            step "qemu-system-${guest}" "${SCRIPT_DIR}/smoke_test_system.sh" "$(cmd "qemu-system-${guest}")" "$guest"
        done
        ;;
    sandbox)
        step "-sandbox" "${SCRIPT_DIR}/smoke_test_sandbox.sh" "$(cmd "qemu-system-${first}")"
        ;;
    system-sandbox)
        for guest in $guests; do
            step "qemu-system-${guest} with -sandbox ${sandbox}" \
                "${SCRIPT_DIR}/smoke_test_system.sh" "$(cmd "qemu-system-${guest}") -sandbox ${sandbox}" "$guest"
        done
        ;;
    *)
        echo "unknown stage: $stage" >&2
        exit 2
        ;;
    esac
done

echo ""
if [ -n "$failed" ]; then
    echo "Smoke tests FAILED on ${host}:${failed}" >&2
    exit 1
fi
echo "All smoke tests passed on ${host}"
