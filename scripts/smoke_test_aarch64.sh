#!/bin/sh
# Smoke tests for the aarch64 halves of the fat binaries on an x86_64 machine,
# by converting a copy of each binary to a native aarch64 ELF and running it
# under qemu-user (qemu-aarch64-static).
#
# Usage:
#   ./scripts/smoke_test_aarch64.sh [output directory (default: ./out)]
#
# Needs assimilate (from cosmocc) and qemu-aarch64-static in PATH.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(cd "${1:-${SCRIPT_DIR}/../out}" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for tool in assimilate qemu-aarch64-static; do
    command -v "$tool" >/dev/null 2>&1 || { echo "$tool not found in PATH" >&2; exit 2; }
done

# aarch64 copy of an APE file: $TMP/<name>
aarch64_copy() {
    cp "${OUT_DIR}/$1.com" "${TMP}/$1"
    assimilate -a -c "${TMP}/$1"
}

echo "Testing qemu-img (aarch64)..."
aarch64_copy qemu-img
"${SCRIPT_DIR}/smoke_test.sh" "qemu-aarch64-static ${TMP}/qemu-img"

for guest in x86_64 aarch64; do
    [ -f "${OUT_DIR}/qemu-system-${guest}.com" ] || continue
    echo ""
    echo "Testing qemu-system-${guest} (aarch64)..."
    aarch64_copy "qemu-system-${guest}"
    SMOKE_HOST_ARCH=aarch64 SMOKE_TIMEOUT=120 \
        "${SCRIPT_DIR}/smoke_test_system.sh" "qemu-aarch64-static ${TMP}/qemu-system-${guest}" "${guest}"
done
