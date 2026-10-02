# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Firmware and SDL2 libraries embedded in the system emulators. Sourced by scripts/build.sh.

# regex of files under share/qemu to embed for <guest>
guest_firmware_regex() {
    case "$1" in
        x86_64) echo '^(bios(-256k|-microvm)?\.bin|qboot\.rom|vgabios.*\.bin|kvmvapic\.bin|linuxboot(_dma)?\.bin|multiboot(_dma)?\.bin|pvh\.bin|sgabios\.bin|efi-.*\.rom|edk2-(x86_64|i386)-.*\.fd|edk2-licenses\.txt|firmware/.*(x86_64|i386).*\.json|keymaps/.+)$' ;;
        aarch64) echo '^(vgabios.*\.bin|efi-.*\.rom|edk2-aarch64-.*\.fd|edk2-licenses\.txt|firmware/.*aarch64.*\.json|keymaps/.+)$' ;;
    esac
}

# stage_firmware <guest> <qemu build dir> <destination>
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

    # Build generated files (edk2 images, keymaps) that do not exist yet; configure-written
    # ones are not ninja targets, so only ask for the missing ones.
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

# stage_sdl2_libraries <destination>
#
# Windows x64 and macOS universal libraries go to share/qemu/sdl2 (used by QEMU patch 18).
# Linux gets none. Archive and extracted library are both pinned, so a changed layout fails here.
stage_sdl2_libraries() {
    local dest=$1 out="$1/share/qemu/sdl2" tmp
    echo "Staging the SDL2 ${SDL2_VERSION} libraries for Windows and macOS..."
    download "${SDL2_WIN_ZIP_SHA256}" "SDL2-${SDL2_VERSION}-win32-x64.zip" \
        "${SDL2_RELEASE_URL}/SDL2-${SDL2_VERSION}-win32-x64.zip"
    download "${SDL2_MAC_DMG_SHA256}" "SDL2-${SDL2_VERSION}.dmg" \
        "${SDL2_RELEASE_URL}/SDL2-${SDL2_VERSION}.dmg"
    rm -rf "${dest}" && mkdir -p "${out}"
    unzip -p "${DL_DIR}/SDL2-${SDL2_VERSION}-win32-x64.zip" SDL2.dll > "${out}/SDL2-windows-x64.dll" \
        || die "SDL2.dll is not in the SDL2 Windows archive"
    # HFS+ image: 7z reads it without mounting
    "${SEVENZIP}" e -so "${DL_DIR}/SDL2-${SDL2_VERSION}.dmg" SDL2/SDL2.framework/Versions/A/SDL2 \
        > "${out}/SDL2-macos-universal.dylib" 2>/dev/null \
        || die "the SDL2 library is not in the SDL2 macOS disk image"
    echo "${SDL2_WIN_DLL_SHA256}  ${out}/SDL2-windows-x64.dll" | sha256sum -c --status \
        || die "SDL2.dll from the Windows archive does not match its pinned SHA-256"
    echo "${SDL2_MAC_DYLIB_SHA256}  ${out}/SDL2-macos-universal.dylib" | sha256sum -c --status \
        || die "the SDL2 library from the macOS disk image does not match its pinned SHA-256"
}
