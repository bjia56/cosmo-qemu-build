#!/bin/sh
# SPDX-License-Identifier: MIT
# Smoke test for a built qemu-img.
# Usage: ./scripts/smoke_test.sh "sh /path/to/qemu-img.com"   (or set $QEMU_IMG)

set -eu

QEMU_IMG="${1:-${QEMU_IMG:-}}"
if [ -z "$QEMU_IMG" ]; then
    echo "usage: $0 <qemu-img command>" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

q() { $QEMU_IMG "$@"; }
pass() { echo "ok   - $1"; }

q --version | head -n 1
pass "--version"

# 1 MiB of non-zero, non-repeating data
i=0
: > a.raw
while [ $i -lt 1024 ]; do
    printf '%01024d' "$i" >> a.raw
    i=$((i + 1))
done

q create -f qcow2 empty.qcow2 64M >/dev/null
q info empty.qcow2 | grep -q 'file format: qcow2'
pass "create + info qcow2"

q convert -f raw -O qcow2 a.raw c.qcow2
q convert -f qcow2 -O raw c.qcow2 b.raw
cmp a.raw b.raw
pass "raw -> qcow2 -> raw round trip"

q check c.qcow2 >/dev/null
pass "check"

q compare a.raw c.qcow2 | grep -q 'identical'
pass "compare"

for fmt in vmdk vdi qed; do
    q convert -f raw -O "$fmt" a.raw "t.$fmt"
    q convert -f "$fmt" -O raw "t.$fmt" "t.$fmt.raw"
    cmp a.raw "t.$fmt.raw"
    pass "raw -> $fmt -> raw round trip"
done

q convert -c -f raw -O qcow2 a.raw cz.qcow2
q check cz.qcow2 >/dev/null
pass "compressed convert"

q convert -c -f raw -O qcow2 -o compression_type=zstd a.raw zs.qcow2
q info zs.qcow2 | grep -q 'compression type: zstd'
q convert -f qcow2 -O raw zs.qcow2 zs.raw
cmp a.raw zs.raw
pass "zstd compressed qcow2 round trip"

q create -f luks --object secret,id=sec0,data=hunter2 -o key-secret=sec0 l.luks 4M >/dev/null
q info --object secret,id=sec0,data=hunter2 --image-opts driver=luks,file.filename=l.luks,key-secret=sec0 | grep -q 'format: luks'
q convert -f raw -O luks --object secret,id=sec0,data=hunter2 -o key-secret=sec0 a.raw lc.luks
q convert --object secret,id=sec0,data=hunter2 --image-opts -O raw driver=luks,file.filename=lc.luks,key-secret=sec0 l.raw
cmp a.raw l.raw
pass "luks encrypted round trip"

q snapshot -c s1 c.qcow2
q snapshot -l c.qcow2 | grep -q s1
pass "snapshot"

q create -f qcow2 -b c.qcow2 -F qcow2 overlay.qcow2 >/dev/null
q info overlay.qcow2 | grep -q 'backing file'
pass "backing file overlay"

echo "All smoke tests passed"
