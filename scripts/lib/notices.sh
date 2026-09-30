#!/bin/bash
# License and third-party notices shipped with the binaries.
# Sourced by scripts/build.sh; relies on the variables it defines.

write_notices() {
    local out=$1
    {
        echo "The QEMU binaries statically link the following libraries."
        echo "QEMU itself is licensed under the GPL-2.0 (see COPYING)."
        echo "Source for the binaries, including all patches, is available at"
        echo "https://github.com/bjia56/cosmo-qemu-build"
        for entry in \
            "glib ${GLIB_VERSION}|${SRC_DIR}/glib/COPYING" \
            "proxy-libintl ${PROXY_LIBINTL_VERSION}|${SRC_DIR}/glib/subprojects/proxy-libintl/COPYING" \
            "pcre2 ${PCRE2_VERSION}|${SRC_DIR}/pcre2-${PCRE2_VERSION}/LICENCE.md" \
            "libffi ${LIBFFI_VERSION}|${SRC_DIR}/libffi-${LIBFFI_VERSION}/LICENSE" \
            "zlib ${ZLIB_VERSION}|${SRC_DIR}/zlib-${ZLIB_VERSION}/LICENSE" \
            "pixman ${PIXMAN_VERSION}|${SRC_DIR}/pixman-${PIXMAN_VERSION}/COPYING"; do
            name="${entry%%|*}"; file="${entry#*|}"
            echo ""
            echo "================================================================"
            echo "${name}"
            echo "================================================================"
            if [ -f "${file}" ]; then cat "${file}"; else echo "(license file not found: ${file##*/})"; fi
        done
        if [ -n "${SYSTEM_TARGETS}" ]; then
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
            echo ""
            echo "================================================================"
            echo "Firmware embedded in the system emulators"
            echo "================================================================"
            echo "SeaBIOS, edk2 and the other firmware and data files under share/qemu are"
            echo "built or bundled by QEMU; see edk2-licenses.txt inside the binaries and"
            echo "the QEMU source tree (pc-bios/README and each component's license)."
        fi
    } > "${out}"
}
