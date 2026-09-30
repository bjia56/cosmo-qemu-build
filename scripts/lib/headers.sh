#!/bin/bash
# Staging of the header files QEMU needs and the sysroot does not have.
# Sourced by scripts/build.sh; relies on the variables it defines.

# stage_kernel_headers <arch> <sysroot>
#
# QEMU's vendored linux/kvm.h includes the base kernel headers (linux/types.h,
# linux/ioctl.h, asm/*, ...), which QEMU expects the host's kernel headers
# package to provide and cosmocc does not ship. Stage only the base headers,
# never kvm.h: QEMU's vendored copy has to win.
stage_kernel_headers() {
    local arch=$1 S=$2
    local var="KERNEL_HEADERS_${arch}" root="" asm="" cand
    if [ -n "${!var:-}" ]; then
        root="${!var}"; asm="${root}/asm"
    elif [ "$arch" = "x86_64" ]; then
        root=/usr/include
        for cand in /usr/include/x86_64-linux-gnu/asm /usr/include/asm; do
            [ -f "${cand}/ioctl.h" ] && asm="$cand" && break
        done
    else
        root=/usr/aarch64-linux-gnu/include; asm="${root}/asm"
    fi
    [ -f "${root}/linux/ioctl.h" ] && [ -f "${asm}/ioctl.h" ] && [ -d "${root}/asm-generic" ] || die \
        "kernel headers for ${arch} not found (looked in ${root}). Install linux-libc-dev
(x86_64) or linux-libc-dev-arm64-cross (aarch64), or set KERNEL_HEADERS_${arch}"

    echo "  staging ${arch} kernel headers from ${root}..."
    mkdir -p "${S}/include/linux" "${S}/include/asm" "${S}/include/asm-generic"
    local f
    for f in ioctl types const stddef posix_types; do
        cp "${root}/linux/${f}.h" "${S}/include/linux/"
    done
    # QEMU's vendored asm/kvm.h includes others (asm/ptrace.h on arm64, ...)
    for f in "${asm}"/*.h; do
        case "$(basename "$f")" in
            kvm*.h) ;;
            *) cp "$f" "${S}/include/asm/" ;;
        esac
    done
    cp -r "${root}/asm-generic/." "${S}/include/asm-generic/"
}

# stage_whp_headers <sysroot>
#
# The Windows Hypervisor Platform headers (winhvplatform.h, ...) are part of
# the mingw-w64 project (ZPL-2.1). They only need a few base Windows types,
# which the headers in compat/whp provide instead of a full Windows SDK. They
# get their own directory, so no generic Windows header name is visible to
# QEMU's or glib's configure probes.
stage_whp_headers() {
    local S=$1 dir="" cand
    for cand in "${WHP_HEADERS:-}" /usr/share/mingw-w64/include /usr/x86_64-w64-mingw32/include; do
        if [ -n "${cand}" ] && [ -f "${cand}/winhvplatform.h" ]; then
            dir="${cand}"
            break
        fi
    done
    [ -n "${dir}" ] || die "WHP headers not found. Install mingw-w64-common (mingw-w64 headers)
or set WHP_HEADERS to a directory containing winhvplatform.h, winhvplatformdefs.h
and winhvemulation.h"
    echo "  staging WHP headers from ${dir}..."
    mkdir -p "${S}/include/whp"
    cp "${PROJECT_ROOT}"/compat/whp/*.h "${S}/include/whp/"
    cp "${dir}/winhvplatform.h" "${dir}/winhvplatformdefs.h" "${dir}/winhvemulation.h" "${S}/include/whp/"
}

# stage_hvf_headers <sysroot>
#
# QEMU's HVF accelerator includes <Hypervisor/Hypervisor.h>. Hypervisor.framework
# cannot be linked into a Cosmopolitan program (it is loaded at run time), so
# compat/hvf provides just the types, constants and prototypes QEMU uses, with
# every call going through a table filled in by cosmo_dlopen().
stage_hvf_headers() {
    local S=$1
    mkdir -p "${S}/include/hvf"
    cp -r "${PROJECT_ROOT}"/compat/hvf/. "${S}/include/hvf/"
}
