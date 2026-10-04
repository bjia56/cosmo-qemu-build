#!/bin/sh
# SPDX-License-Identifier: MIT
# Smoke test for a built qemu-system-* emulator.
# Usage: ./scripts/smoke_test_system.sh "sh /path/to/qemu-system-x86_64.com" x86_64|aarch64
# Firmware is deliberately not passed with -L: it must come from the embedded /zip.
# Runs with TCG, plus KVM when /dev/kvm is usable and the guest matches the host.

set -eu

QEMU="${1:-${QEMU_SYSTEM:-}}"
GUEST="${2:-${QEMU_GUEST:-}}"
if [ -z "$QEMU" ] || [ -z "$GUEST" ]; then
    echo "usage: $0 <qemu-system command> <x86_64|aarch64>" >&2
    exit 2
fi

. "$(dirname "$0")/lib/smoke_common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

TIMEOUT="${SMOKE_TIMEOUT:-60}"

# run_guest <expected text> <qemu args...>: run until the text appears on the serial console or the timeout expires
run_guest() {
    expect=$1; shift
    : > out.txt
    $QEMU -nographic -monitor none -parallel none -no-reboot -m 64 "$@" > out.txt 2>&1 &
    pid=$!
    n=0
    while [ $n -lt "$TIMEOUT" ]; do
        if grep -a -q -E "$expect" out.txt 2>/dev/null; then
            stop_pid $pid
            return 0
        fi
        kill -0 $pid 2>/dev/null || break
        sleep 1
        n=$((n + 1))
    done
    stop_pid $pid
    return 1
}

host_arch=$(uname -m)
case "$host_arch" in arm64) host_arch=aarch64 ;; amd64) host_arch=x86_64 ;; esac

$QEMU --version | head -n 1
pass "--version"

accels=$($QEMU -accel help)
echo "$accels" | grep -q '^tcg$' || fail "-accel help lists tcg"
if [ "$host_arch" = "$GUEST" ]; then
    echo "$accels" | grep -q '^kvm$' || fail "-accel help lists kvm (host arch matches guest)"
    if [ "$GUEST" = "x86_64" ]; then
        # WHPX is compiled in everywhere but only works on Windows
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
    MACHINE_ARGS="-machine pc -accel tcg"
    GPU_ARGS="-vga std"
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

    # WHPX must fail cleanly off Windows. On Windows it is real: it works where the Windows
    # Hypervisor Platform is enabled and fails otherwise, so it is only tried there
    case "$host" in
    windows)
        if run_guest "COSMO-X86-BOOT-OK" -machine pc -accel whpx -drive format=raw,file=boot.img,if=floppy; then
            pass "boot sector on pc (WHPX)"
        else
            echo "skip - WHPX boot test (Windows Hypervisor Platform not usable here)"
        fi
        ;;
    *)
        if [ "$host_arch" = "x86_64" ]; then
            if $QEMU -machine pc -accel whpx -display none -monitor none -parallel none -S > out.txt 2>&1; then
                fail "-accel whpx must fail on a non-Windows host"
            fi
            grep -a -q 'only available when running on Windows' out.txt \
                || fail "-accel whpx reports a clear error on a non-Windows host"
            pass "-accel whpx fails cleanly on a non-Windows host"
        fi
        ;;
    esac

    if [ "$host_arch" = "x86_64" ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        run_guest "COSMO-X86-BOOT-OK" -machine pc -accel kvm -drive format=raw,file=boot.img,if=floppy \
            || fail "boot sector on pc (KVM)"
        pass "boot sector on pc (KVM)"
    else
        echo "skip - KVM boot test (no usable /dev/kvm)"
    fi
    ;;
aarch64)
    MACHINE_ARGS="-machine virt -cpu cortex-a57 -accel tcg"
    GPU_ARGS="-device virtio-gpu-pci"
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

# monitor_cmds <monitor commands> <qemu args...>: run the commands in a paused emulator's monitor, output to out.txt
monitor_cmds() {
    cmds=$1; shift
    printf '%s\nquit\n' "$cmds" > cmds.txt
    : > out.txt
    $QEMU -S -display none -serial none -parallel none -monitor stdio -m 64 $MACHINE_ARGS "$@" \
        < cmds.txt > out.txt 2>&1 &
    pid=$!
    n=0
    while [ $n -lt "$TIMEOUT" ] && kill -0 $pid 2>/dev/null; do
        sleep 1
        n=$((n + 1))
    done
    if kill -0 $pid 2>/dev/null; then
        stop_pid $pid
        return 1
    fi
    wait $pid 2>/dev/null || true
}

# only needs to be unlikely to clash
PORT=$((20000 + $$ % 20000))

monitor_cmds "info usernet" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${PORT}-:22" -device virtio-net-pci,netdev=n0 \
    || fail "user networking (monitor did not finish)"
grep -a -q 'HOST_FORWARD' out.txt || fail "user networking lists the hostfwd rule"
grep -a -q "${PORT}" out.txt || fail "user networking forwards the requested port"
pass "user-mode networking (libslirp) with a host forward"

# needs the sscanf replacement (QEMU patch 10)
cat > cfg.conf <<EOF
[chardev "c0"]
  backend = "null"
EOF
monitor_cmds "info chardev
info network" \
    -serial "tcp:127.0.0.1:$((PORT + 1)),server,nowait" -readconfig cfg.conf \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -global virtio-net-pci.mac=52:54:00:aa:bb:cc \
    || fail "option parsing (monitor did not finish)"
grep -a -q "tcp:127.0.0.1:$((PORT + 1))" out.txt || fail "-serial tcp:host:port shorthand"
grep -a -q "c0: filename=null" out.txt || fail "-readconfig chardev"
grep -a -q '52:54:00:aa:bb:cc' out.txt || fail "-global property reaches the device"
pass "-serial tcp: shorthand, -readconfig and -global parsing"

monitor_cmds "screendump shot.ppm
screendump shot.png -f png" $GPU_ARGS \
    || fail "screendump (monitor did not finish)"
[ "$(head -c 2 shot.ppm)" = "P6" ] || fail "screendump writes a PPM"
# the PNG signature: 89 50 4e 47 0d 0a 1a 0a
[ "$(head -c 8 shot.png | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ] || fail "screendump -f png writes a PNG"
pass "screendump as PPM and PNG"

# virtfs: mapped-xattr and passthrough only work on Linux
mkdir share9p
models="none mapped-file"
case "$(uname -s)" in Linux) models="$models mapped-xattr passthrough" ;; esac
for model in $models; do
    monitor_cmds "info qtree" \
        -fsdev "local,id=f0,path=share9p,security_model=${model}" \
        -device virtio-9p-pci,fsdev=f0,mount_tag=cosmo9p \
        || fail "virtfs ${model} (monitor did not finish)"
    grep -a -q 'mount_tag = "cosmo9p"' out.txt || fail "virtfs ${model}: virtio-9p device with its mount tag"
done
pass "virtio-9p (virtfs) with a local fsdev: $models"

# crashed with Cosmopolitan's default thread stack (QEMU patch 16)
monitor_cmds "info vnc" -vnc "127.0.0.1:$((PORT + 2)),websocket=127.0.0.1:$((PORT + 3))" \
    || fail "vnc (monitor did not finish)"
grep -a -q "127.0.0.1:$((5900 + PORT + 2))" out.txt || fail "vnc server listens on the requested display"
pass "VNC server with a WebSocket listener"

mkdir psk
echo "cosmo:0123456789abcdef0123456789abcdef" > psk/keys.psk
monitor_cmds "info chardev" \
    -object tls-creds-psk,id=tls0,endpoint=server,dir=psk \
    -chardev "socket,id=c0,host=127.0.0.1,port=$((PORT + 4)),server=on,wait=off,tls-creds=tls0" \
    || fail "tls (monitor did not finish)"
grep -a -q "c0: filename=" out.txt || fail "tls-creds-psk with a chardev socket (gnutls)"
pass "TLS credentials (gnutls) on a chardev socket"

# Without SDL2 this must fail with a clear message, not crash (smoke_test_sdl.sh checks the window)
monitor_cmds "quit" -display sdl -net none \
    || fail "sdl display (monitor did not finish)"
if grep -a -q "lacks SDL_\|undefined symbol" out.txt; then fail "sdl display: SDL2 binding"; fi
if grep -a -q "cannot load the SDL2 library" out.txt; then
    pass "-display sdl reports a missing SDL2 library cleanly"
else
    pass "-display sdl with the host's SDL2"
fi

echo "All system emulator smoke tests passed"
