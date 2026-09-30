#!/bin/sh
# SPDX-License-Identifier: MIT
# Smoke test for a built qemu-system-* emulator.
#
# Usage:
#   ./scripts/smoke_test_system.sh "sh /path/to/qemu-system-x86_64.com" x86_64
#   ./scripts/smoke_test_system.sh "sh /path/to/qemu-system-aarch64.com" aarch64
#
# The first argument is the full command used to invoke the emulator (so APE
# binaries can be run through `sh` on hosts without an APE loader); the second
# is the guest architecture. Firmware is deliberately not passed with -L: it is
# expected to be found in the binary's embedded /zip/share/qemu.
#
# Tests run with the TCG accelerator. If /dev/kvm is usable and the guest
# matches the host architecture, the boot test is repeated with KVM.

set -eu

QEMU="${1:-${QEMU_SYSTEM:-}}"
GUEST="${2:-${QEMU_GUEST:-}}"
if [ -z "$QEMU" ] || [ -z "$GUEST" ]; then
    echo "usage: $0 <qemu-system command> <x86_64|aarch64>" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

TIMEOUT="${SMOKE_TIMEOUT:-60}"
pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; [ -f out.txt ] && tail -n 20 out.txt >&2; exit 1; }

# run_guest <expected text> <qemu args...>: run until the text shows up on the
# serial console (or the timeout expires), then stop the guest
run_guest() {
    expect=$1; shift
    : > out.txt
    $QEMU -nographic -monitor none -parallel none -no-reboot -m 64 "$@" > out.txt 2>&1 &
    pid=$!
    n=0
    while [ $n -lt "$TIMEOUT" ]; do
        if grep -a -q -E "$expect" out.txt 2>/dev/null; then
            kill $pid 2>/dev/null || true
            wait $pid 2>/dev/null || true
            return 0
        fi
        kill -0 $pid 2>/dev/null || break
        sleep 1
        n=$((n + 1))
    done
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
    return 1
}

# The architecture the emulator binary itself runs as. Override it when testing
# a slice under user-mode emulation (e.g. SMOKE_HOST_ARCH=aarch64 with
# qemu-aarch64-static on an x86_64 machine).
host_arch=${SMOKE_HOST_ARCH:-$(uname -m)}
case "$host_arch" in arm64) host_arch=aarch64 ;; amd64) host_arch=x86_64 ;; esac

$QEMU --version | head -n 1
pass "--version"

accels=$($QEMU -accel help)
echo "$accels" | grep -q '^tcg$' || fail "-accel help lists tcg"
if [ "$host_arch" = "$GUEST" ]; then
    echo "$accels" | grep -q '^kvm$' || fail "-accel help lists kvm (host arch matches guest)"
    if [ "$GUEST" = "x86_64" ]; then
        # WHPX is compiled into the x86_64 slice everywhere and only works on
        # Windows; elsewhere selecting it must fail cleanly
        echo "$accels" | grep -q '^whpx$' || fail "-accel help lists whpx (x86_64 guest on x86_64 host)"
        pass "-accel help lists tcg, kvm and whpx"
    else
        pass "-accel help lists tcg and kvm"
    fi
else
    pass "-accel help lists tcg (no KVM expected: host $host_arch, guest $GUEST)"
fi

case "$GUEST" in
x86_64)
    # Boot sector that prints a message on COM1, waiting for the UART each byte
    printf '\276\035\174\254\204\300\164\022\210\303\272\375\003\354\250\040\164\370\272\370\003\210\330\356\353\351\364\353\375COSMO-X86-BOOT-OK\r\n\0' > boot.img
    pad=$((510 - $(wc -c < boot.img)))
    head -c $pad /dev/zero >> boot.img
    printf '\125\252' >> boot.img

    run_guest "COSMO-X86-BOOT-OK" -machine pc -accel tcg -drive format=raw,file=boot.img,if=floppy \
        || fail "boot sector on pc (TCG)"
    grep -a -q 'SeaBIOS' out.txt || fail "SeaBIOS banner (embedded firmware)"
    pass "boot sector on pc with embedded SeaBIOS (TCG)"

    run_guest "COSMO-X86-BOOT-OK" -machine q35 -accel tcg -drive format=raw,file=boot.img,if=floppy \
        || fail "boot sector on q35 (TCG)"
    pass "boot sector on q35 (TCG)"

    run_guest "COSMO-X86-BOOT-OK" -machine pc,accel=kvm:tcg -drive format=raw,file=boot.img,if=floppy \
        || fail "boot sector with kvm:tcg fallback"
    pass "boot sector with accel=kvm:tcg (KVM or fallback)"

    # WHPX is loaded with cosmo_dlopen and only works on Windows; on the
    # Unix hosts this script runs on, asking for it has to fail cleanly
    if [ "$host_arch" = "x86_64" ]; then
        if $QEMU -machine pc -accel whpx -display none -monitor none -parallel none -S > out.txt 2>&1; then
            fail "-accel whpx must fail on a non-Windows host"
        fi
        grep -a -q 'only available when running on Windows' out.txt \
            || fail "-accel whpx reports a clear error on a non-Windows host"
        pass "-accel whpx fails cleanly on a non-Windows host"
    fi

    if [ "$host_arch" = "x86_64" ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        run_guest "COSMO-X86-BOOT-OK" -machine pc -accel kvm -drive format=raw,file=boot.img,if=floppy \
            || fail "boot sector on pc (KVM)"
        pass "boot sector on pc (KVM)"
    else
        echo "skip - KVM boot test (no usable /dev/kvm)"
    fi
    ;;
aarch64)
    # Bare-metal payload for the virt machine's PL011 UART at 0x09000000. It is loaded
    # above the start of RAM, where virt puts its device tree.
    printf '\001\040\241\322\342\000\000\020\103\024\100\070\143\000\000\064\043\000\000\071\375\377\377\027\177\040\003\325\377\377\377\027COSMO-AARCH64-BOOT-OK\n\0' > payload.bin

    run_guest "COSMO-AARCH64-BOOT-OK" -machine virt -cpu cortex-a57 -accel tcg \
        -device loader,file=payload.bin,addr=0x40200000,cpu-num=0 \
        || fail "bare-metal payload on virt (TCG)"
    pass "bare-metal payload on virt (TCG)"

    # -bios resolves through QEMU's data directory, i.e. the embedded /zip
    run_guest "UEFI|EDK II|Tianocore|BdsDxe" -machine virt -cpu cortex-a57 -accel tcg \
        -bios edk2-aarch64-code.fd \
        || fail "edk2 firmware from embedded data directory"
    pass "edk2-aarch64 firmware from embedded data directory (TCG)"

    if [ "$host_arch" = "aarch64" ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        run_guest "COSMO-AARCH64-BOOT-OK" -machine virt -cpu host -accel kvm \
            -device loader,file=payload.bin,addr=0x40200000,cpu-num=0 \
            || fail "bare-metal payload on virt (KVM)"
        pass "bare-metal payload on virt (KVM)"
    else
        echo "skip - KVM boot test (no usable /dev/kvm)"
    fi
    ;;
*)
    echo "unsupported guest architecture: $GUEST" >&2
    exit 2
    ;;
esac

echo "All system emulator smoke tests passed"
