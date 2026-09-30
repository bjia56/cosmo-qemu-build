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
# QEMU's WHPX code includes the Windows Hypervisor Platform headers. Microsoft
# publishes them under the MIT license (see the header of each file) in
# https://github.com/MicrosoftDocs/Virtualization-Documentation; they are fetched
# from a pinned commit and checked by SHA-256. They only need a few base Windows
# types and macros, which the headers in compat/whp provide instead of a full
# Windows SDK. They get their own directory, so no generic Windows header name is
# visible to QEMU's or glib's configure probes. The files are named in mixed case
# and include each other that way, while QEMU includes them in lower case.
stage_whp_headers() {
    local S=$1 f
    echo "  staging WHP headers..."
    for f in "${!WHP_HEADER_SHA256[@]}"; do
        download "${WHP_HEADER_SHA256[$f]}" "${f}" "${WHP_HEADERS_URL}/${f}"
    done
    mkdir -p "${S}/include/whp"
    cp "${PROJECT_ROOT}"/compat/whp/*.h "${S}/include/whp/"
    for f in "${!WHP_HEADER_SHA256[@]}"; do
        cp "${DL_DIR}/${f}" "${S}/include/whp/${f}"
        cp "${DL_DIR}/${f}" "${S}/include/whp/$(echo "${f}" | tr 'A-Z' 'a-z')"
    done
}

# stage_hvf_headers <sysroot>
#
# QEMU's HVF accelerator includes <Hypervisor/Hypervisor.h>. Hypervisor.framework
# cannot be linked into a Cosmopolitan program (it is loaded at run time), and its
# own headers cannot be used with cosmocc (they need clang and the Darwin system
# headers), so compat/hvf provides just the types, constants and prototypes QEMU
# uses, with every call going through a table filled in by cosmo_dlopen(). The
# system register identifiers are the Arm architectural encodings, which QEMU's
# own table (hvf_sreg_match in target/arm/hvf/hvf.c) lists as
# (CRn, CRm, op0, op1, op2); they are generated from that table.
stage_hvf_headers() {
    local S=$1
    mkdir -p "${S}/include/hvf"
    cp -r "${PROJECT_ROOT}"/compat/hvf/. "${S}/include/hvf/"
    python3 - "${SRC_DIR}/qemu/target/arm/hvf/hvf.c" "${S}/include/hvf/Hypervisor/hvf-sysregs.h" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
regs = {}
for m in re.finditer(r'\{\s*(HV_SYS_REG_[A-Z0-9_]+),\s*HVF_SYSREG\(\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\)', src):
    name = m.group(1)
    crn, crm, op0, op1, op2 = map(int, m.groups()[1:])
    regs[name] = (op0 << 14) | (op1 << 11) | (crn << 7) | (crm << 3) | op2
if not regs:
    sys.exit("no system registers found in " + sys.argv[1])
with open(sys.argv[2], "w") as f:
    f.write("/* Generated from QEMU's hvf_sreg_match table: op0<<14 | op1<<11 | CRn<<7 | CRm<<3 | op2 */\nenum {\n")
    for name in sorted(regs):
        f.write("    %s = 0x%x,\n" % (name, regs[name]))
    f.write("};\n")
PYEOF
}
