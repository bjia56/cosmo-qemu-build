# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Staging of headers the sysroot lacks. Sourced by scripts/build.sh.

# stage_kernel_headers <arch> <sysroot>
#
# QEMU's vendored linux/kvm.h needs the base kernel headers, which cosmocc lacks.
# Never stage kvm.h: QEMU's vendored copy has to win.
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
    # QEMU's asm/kvm.h includes others (asm/ptrace.h on arm64)
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
# Microsoft's MIT-licensed WHP headers (MicrosoftDocs/Virtualization-Documentation,
# pinned commit). compat/whp/minwindef.h supplies the base Windows types they need.
# A private directory keeps generic Windows header names away from configure probes.
# They include each other in mixed case, QEMU in lower case, hence both copies.
stage_whp_headers() {
    local S=$1 f
    echo "  staging WHP headers..."
    for f in "${!WHP_HEADER_SHA256[@]}"; do
        download "${WHP_HEADER_SHA256[$f]}" "${f}" "${WHP_HEADERS_URL}/${f}"
    done
    mkdir -p "${S}/include/whp"
    cp "${PROJECT_ROOT}"/compat/whp/*.h "${S}/include/whp/"
    # other SDK headers they include; minwindef.h covers them
    for f in apiset.h apisetcconv.h winapifamily.h; do
        echo "/* intentionally empty: see minwindef.h */" > "${S}/include/whp/${f}"
    done
    for f in "${!WHP_HEADER_SHA256[@]}"; do
        cp "${DL_DIR}/${f}" "${S}/include/whp/${f}"
        cp "${DL_DIR}/${f}" "${S}/include/whp/${f,,}"
    done
}

# stage_hvf_headers <sysroot>
#
# Apple's own headers need clang and Darwin headers, so compat/hvf provides the
# subset QEMU uses. The system register identifiers are generated from QEMU's
# hvf_sreg_match table (target/arm/hvf/hvf.c).
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

# Copy the sscanf replacement (compat/scanf) into QEMU and libslirp; their 10-/02-cosmo-sscanf-scansets patches use it.
stage_scanf_shim() {
    local c="${PROJECT_ROOT}/compat/scanf"
    local slirp="${SRC_DIR}/libslirp-v${LIBSLIRP_VERSION}/src"
    cp "${c}/cosmo-sscanf.h" "${SRC_DIR}/qemu/include/qemu/"
    cp "${c}/cosmo-sscanf.c" "${SRC_DIR}/qemu/util/"
    cp "${c}/cosmo-sscanf.h" "${c}/cosmo-sscanf.c" "${slirp}/"
}

# stage_sdl2_headers <sysroot>
#
# Headers only: SDL2 is loaded at run time (QEMU patch 17). A cflags-only
# pkg-config file stands in for SDL2's own.
stage_sdl2_headers() {
    local S=$1
    echo "  staging SDL2 headers..."
    mkdir -p "${S}/include/SDL2" "${S}/lib/pkgconfig"
    cp "${SRC_DIR}/SDL2-${SDL2_VERSION}"/include/*.h "${S}/include/SDL2/"
    cat > "${S}/lib/pkgconfig/sdl2.pc" <<PCEND
prefix=${S}
Name: sdl2
Description: SDL2 headers only; the library is loaded at run time
Version: ${SDL2_VERSION}
Cflags: -I${S}/include/SDL2
Libs:
PCEND
}
