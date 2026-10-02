# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# License and third-party notices, embedded in every executable.
# Sourced by scripts/build.sh; relies on the variables it defines.

# write_notices <output file>
write_notices() {
    local out=$1 entry name file
    {
        echo "These executables are built from QEMU, which is licensed under the GPL-2.0"
        echo "(see COPYING in this archive), and statically link the libraries below."
        echo "Source for the executables, including all patches and build scripts, is at"
        echo "https://github.com/bjia56/cosmo-qemu-build"
        for entry in \
            "Cosmopolitan Libc ${COSMOPOLITAN_VERSION}|${DL_DIR}/cosmopolitan-LICENSE" \
            "glib ${GLIB_VERSION}|${SRC_DIR}/glib/COPYING" \
            "proxy-libintl ${PROXY_LIBINTL_VERSION}|${SRC_DIR}/glib/subprojects/proxy-libintl/COPYING" \
            "libpng ${LIBPNG_VERSION}|${SRC_DIR}/libpng-${LIBPNG_VERSION}/LICENSE" \
            "libjpeg-turbo ${LIBJPEG_TURBO_VERSION}|${SRC_DIR}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}/LICENSE.md" \
            "pcre2 ${PCRE2_VERSION}|${SRC_DIR}/pcre2-${PCRE2_VERSION}/LICENCE.md" \
            "nettle ${NETTLE_VERSION} (used under GPL-2.0-or-later)|${SRC_DIR}/nettle-${NETTLE_VERSION}/COPYINGv2" \
            "bzip2 ${BZIP2_VERSION}|${SRC_DIR}/bzip2-${BZIP2_VERSION}/LICENSE" \
            "zstd ${ZSTD_VERSION}|${SRC_DIR}/zstd-${ZSTD_VERSION}/LICENSE" \
            "libffi ${LIBFFI_VERSION}|${SRC_DIR}/libffi-${LIBFFI_VERSION}/LICENSE" \
            "zlib ${ZLIB_VERSION}|${SRC_DIR}/zlib-${ZLIB_VERSION}/LICENSE" \
            "pixman ${PIXMAN_VERSION}|${SRC_DIR}/pixman-${PIXMAN_VERSION}/COPYING" \
            "libslirp ${LIBSLIRP_VERSION}|${SRC_DIR}/libslirp-v${LIBSLIRP_VERSION}/COPYRIGHT"; do
            name="${entry%%|*}"; file="${entry#*|}"
            echo ""
            echo "================================================================"
            echo "${name}"
            echo "================================================================"
            if [ "${name%% *}" = "Cosmopolitan" ]; then
                echo "The notices of the third-party code that Cosmopolitan Libc bundles are"
                echo "embedded in the executables themselves (they appear in the output of strings(1))."
                echo ""
            fi
            if [ -f "${file}" ]; then cat "${file}"; else echo "(license file not found: ${file##*/})"; fi
        done
        if [ -f "${DL_DIR}/WinHvPlatform.h" ]; then
            echo ""
            echo "================================================================"
            echo "Windows Hypervisor Platform headers (build time only)"
            echo "================================================================"
            echo "The qemu-system-x86_64 build for x86_64 hosts is compiled against the"
            echo "WinHvPlatform.h, WinHvPlatformDefs.h and WinHvEmulation.h headers that Microsoft"
            echo "publishes at https://github.com/MicrosoftDocs/Virtualization-Documentation,"
            echo "for the type and constant definitions of the WHPX accelerator, under this license:"
            echo ""
            sed -n '1,18p' "${DL_DIR}/WinHvPlatform.h"
        fi
        if [ -n "${SYSTEM_TARGETS}" ]; then
            echo ""
            echo "================================================================"
            echo "Firmware embedded in the system emulators"
            echo "================================================================"
            echo "SeaBIOS, edk2 and the other firmware and data files under share/qemu are"
            echo "built or bundled by QEMU; see edk2-licenses.txt inside the executables and"
            echo "the QEMU source tree (pc-bios/README and each component's license)."
        fi
    } > "${out}"
}

# prepare_licenses
#
# COPYING and THIRD_PARTY_NOTICES.txt are stored inside every executable
# (Cosmopolitan serves the zip archive appended to it), so nothing has to be
# distributed next to the binaries:
#   unzip -p qemu-img.com COPYING
prepare_licenses() {
    LICENSE_DIR="${BUILD_DIR}/licenses"
    mkdir -p "${LICENSE_DIR}"
    cp "${SRC_DIR}/qemu/COPYING" "${LICENSE_DIR}/COPYING"
    write_notices "${LICENSE_DIR}/THIRD_PARTY_NOTICES.txt"
}

# embed_licenses <executable>
embed_licenses() {
    (cd "${LICENSE_DIR}" && zip -q "$1" COPYING THIRD_PARTY_NOTICES.txt)
    python3 - "$1" <<'PYEOF'
import sys, zipfile
names = zipfile.ZipFile(sys.argv[1]).namelist()
for f in ("COPYING", "THIRD_PARTY_NOTICES.txt"):
    if f not in names:
        sys.exit("%s is missing from %s" % (f, sys.argv[1]))
PYEOF
}
