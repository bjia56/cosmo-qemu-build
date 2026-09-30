# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Selecting and staging the firmware embedded in the system emulators.
# Sourced by scripts/build.sh; relies on the variables it defines.

# guest_firmware_files <guest>: regex of files under share/qemu to embed
guest_firmware_regex() {
    case "$1" in
        x86_64) echo '^(bios(-256k|-microvm)?\.bin|qboot\.rom|vgabios.*\.bin|kvmvapic\.bin|linuxboot(_dma)?\.bin|multiboot(_dma)?\.bin|pvh\.bin|sgabios\.bin|efi-.*\.rom|edk2-(x86_64|i386)-.*\.fd|edk2-licenses\.txt|firmware/.*(x86_64|i386).*\.json|keymaps/.+)$' ;;
        aarch64) echo '^(vgabios.*\.bin|efi-.*\.rom|edk2-aarch64-.*\.fd|edk2-licenses\.txt|firmware/.*aarch64.*\.json|keymaps/.+)$' ;;
    esac
}

# stage_firmware <guest> <qemu build dir> <destination>
#
# Build and copy the subset of QEMU's installed data files that one guest
# architecture needs into <destination>/share/qemu.
stage_firmware() {
    local guest=$1 qb=$2 dest=$3
    local list="${qb}/fw-${guest}.tsv"
    "${qb}/pyvenv/bin/meson" introspect --installed "${qb}" | python3 -c '
import json, os, re, sys
qb, guest_re, out = sys.argv[1:4]
want = re.compile(guest_re)
rows = []
for src, dst in json.load(sys.stdin).items():
    if "/share/qemu/" not in dst:
        continue
    rel = dst.split("/share/qemu/", 1)[1]
    if want.match(rel):
        rows.append((src, rel))
with open(out, "w") as f:
    for src, rel in sorted(rows, key=lambda r: r[1]):
        f.write("%s\t%s\n" % (src, rel))
' "${qb}" "$(guest_firmware_regex "$guest")" "${list}"
    [ -s "${list}" ] || die "no firmware selected for ${guest}"

    # Generated files under the build directory that do not exist yet have to
    # be built (edk2 images are decompressed, keymaps generated). Some, like
    # the firmware descriptors, are written by configure and are not ninja
    # targets at all, so only ask for the missing ones.
    local targets="" src rel
    while IFS=$'\t' read -r src rel; do
        if [ ! -f "${src}" ] && [ "${src#"${qb}/"}" != "${src}" ]; then
            targets+=" ${src#"${qb}/"}"
        fi
    done < "${list}"
    if [ -n "${targets}" ]; then
        # shellcheck disable=SC2086
        (cd "${qb}" && ninja -j"${JOBS}" ${targets}) >"${LOG_DIR}/firmware-${guest}.log" 2>&1 \
            || { tail -n 30 "${LOG_DIR}/firmware-${guest}.log" >&2; die "building firmware for ${guest} failed"; }
    fi

    rm -rf "${dest}"
    while IFS=$'\t' read -r src rel; do
        [ -f "${src}" ] || die "firmware file missing: ${src}"
        mkdir -p "${dest}/share/qemu/$(dirname "${rel}")"
        cp "${src}" "${dest}/share/qemu/${rel}"
    done < "${list}"
    echo "  staged $(wc -l < "${list}") firmware files for ${guest} ($(du -sh "${dest}" | cut -f1))"
}
