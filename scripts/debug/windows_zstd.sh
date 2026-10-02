#!/bin/sh
# TEMPORARY: narrows down the qemu-img crash on a zstd-compressed qcow2 on Windows.
# Usage: windows_zstd.sh <qemu-img.exe>
set -u
Q="$1"
TMP="$(mktemp -d)"; cd "$TMP"

i=0; : > a.raw
while [ $i -lt 1024 ]; do printf '%01024d' "$i" >> a.raw; i=$((i + 1)); done
head -c 4096 a.raw > s4k.raw
head -c 65536 a.raw > s64k.raw
head -c 1048576 /dev/zero > zeros.raw

# run <label> <args...>: print the exit status and the last lines of output
run() {
    label=$1; shift
    $Q "$@" > out.txt 2>&1
    rc=$?
    echo "RESULT [$label] rc=$rc :: $(tail -n 2 out.txt | tr '\n' '|' | cut -c1-200)"
}

echo "== qemu-img version"; $Q --version | head -n 1
run "zlib -c (control)"            convert -c -f raw -O qcow2 a.raw z.qcow2
run "zstd -c 1MiB"                 convert -c -f raw -O qcow2 -o compression_type=zstd a.raw zs.qcow2
run "zstd -c 4KiB"                 convert -c -f raw -O qcow2 -o compression_type=zstd s4k.raw zs4.qcow2
run "zstd -c 64KiB"                convert -c -f raw -O qcow2 -o compression_type=zstd s64k.raw zs64.qcow2
run "zstd -c zeros"                convert -c -f raw -O qcow2 -o compression_type=zstd zeros.raw zsz.qcow2
run "zstd -c -m 1"                 convert -c -m 1 -f raw -O qcow2 -o compression_type=zstd a.raw zsm1.qcow2
run "zstd -c -W"                   convert -c -W -f raw -O qcow2 -o compression_type=zstd a.raw zsw.qcow2
run "zstd -c cluster 4k"           convert -c -f raw -O qcow2 -o compression_type=zstd,cluster_size=4096 a.raw zsc.qcow2
run "zstd create only"             create -f qcow2 -o compression_type=zstd c0.qcow2 1M
run "zstd no -c (uncompressed)"    convert -f raw -O qcow2 -o compression_type=zstd a.raw zsn.qcow2
run "zlib -c 4KiB"                 convert -c -f raw -O qcow2 s4k.raw z4.qcow2

echo "== strace tail of the 1 MiB zstd case"
$Q --strace convert -c -f raw -O qcow2 -o compression_type=zstd a.raw zst.qcow2 > strace.txt 2>&1
echo "rc=$? lines=$(wc -l < strace.txt)"
tail -n 120 strace.txt
