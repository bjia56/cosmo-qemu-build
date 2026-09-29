#!/bin/bash
# Build script for qemu-img and the QEMU system emulators with Cosmopolitan libc
#
# This script builds QEMU separately for x86_64 and aarch64 hosts using the
# arch-specific Cosmopolitan compilers, then uses apelink to combine the two
# into a single fat binary per program that runs on multiple platforms.
#
# Outputs:
#   src/cosmo_qemu_img/data/qemu-img.com     qemu-img (packaged as the Python wheel)
#   out/qemu-system-<guest>.com              one system emulator per guest
#                                            architecture, with KVM compiled in
#                                            where the guest matches the host
#                                            architecture (plus TCG everywhere)
#                                            and its firmware embedded in /zip
#
# The emulators pick an accelerator at run time (-machine accel=kvm:tcg): KVM
# only works on Linux hosts where /dev/kvm is usable and the guest architecture
# matches the host's, otherwise QEMU falls back to TCG.
#
# QEMU needs glib (which needs libffi, pcre2 and a libintl), pixman and zlib.
# None of those are provided by cosmocc, so they are built from source into a
# per-architecture static sysroot first.
#
# Requirements:
#   - cosmocc compiler toolchain (https://cosmo.zip/pub/cosmocc/)
#   - git, curl, make, patch, zip, bzip2, ninja, python3, meson (>= 1.5), pkg-config
#   - qemu-aarch64-static, to run aarch64 configure-time probes
#     (or set EXE_WRAPPER_aarch64 to another wrapper)
#   - Linux kernel headers for each host architecture, for QEMU's KVM code:
#     linux-libc-dev (x86_64) and linux-libc-dev-arm64-cross (aarch64), or point
#     KERNEL_HEADERS_<arch> at a directory containing linux/, asm/ and asm-generic/
#
# Usage:
#   ./scripts/build.sh
#
# Optional environment:
#   JOBS                 parallel build jobs (default: nproc)
#   ARCHES               host architectures (default: "x86_64 aarch64")
#   SYSTEM_TARGETS       guest architectures to build emulators for
#                        (default: "x86_64 aarch64"; empty builds qemu-img only)
#   BUILD_DIR            build tree location (default: ./build)
#   OUT_DIR              emulator output location (default: ./out)
#   EXE_WRAPPER_<arch>   command used to run <arch> test programs
#   KERNEL_HEADERS_<arch> kernel header tree for <arch>
#   QEMU_REPO            QEMU git URL
#   GLIB_REPO            glib git URL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/out}"
DL_DIR="${BUILD_DIR}/dl"
LOG_DIR="${BUILD_DIR}/logs"
SRC_DIR="${BUILD_DIR}/source"
TOOLS_DIR="${BUILD_DIR}/tools"
OUTPUT_DIR="${PROJECT_ROOT}/src/cosmo_qemu_img/data"
OUTPUT_BINARY="${OUTPUT_DIR}/qemu-img.com"
OUTPUT_LICENSE="${OUTPUT_DIR}/COPYING"
OUTPUT_NOTICES="${OUTPUT_DIR}/THIRD_PARTY_NOTICES.txt"

JOBS="${JOBS:-$(nproc)}"
ARCHES="${ARCHES:-x86_64 aarch64}"
SYSTEM_TARGETS="${SYSTEM_TARGETS-x86_64 aarch64}"

# QEMU version comes from the Python module so the package and the build agree
QEMU_VERSION=$(python3 -c "import sys; sys.path.insert(0, '${PROJECT_ROOT}/src'); from cosmo_qemu_img._version import QEMU_GIT_TAG; print(QEMU_GIT_TAG)")
QEMU_REPO="${QEMU_REPO:-https://gitlab.com/qemu-project/qemu.git}"

# Dependencies, built into the sysroot. Tarballs are verified by SHA-256.
GLIB_VERSION="2.82.4"
GLIB_REPO="${GLIB_REPO:-https://github.com/GNOME/glib.git}"
PROXY_LIBINTL_VERSION="0.4"
PROXY_LIBINTL_REPO="https://github.com/frida/proxy-libintl.git"

ZLIB_VERSION="1.3.1"
ZLIB_URLS=("https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz")
ZLIB_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"

PCRE2_VERSION="10.44"
PCRE2_URLS=("https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.bz2")
PCRE2_SHA256="d34f02e113cf7193a1ebf2770d3ac527088d485d4e047ed10e5d217c6ef5de96"

LIBFFI_VERSION="3.4.6"
LIBFFI_URLS=("https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz")
LIBFFI_SHA256="b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e"

# The first mirror hosts the upstream tarball as a Debian/Ubuntu "orig" file
PIXMAN_VERSION="0.44.0"
PIXMAN_URLS=(
    "http://archive.ubuntu.com/ubuntu/pool/main/p/pixman/pixman_${PIXMAN_VERSION}.orig.tar.gz"
    "https://cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz"
)
PIXMAN_SHA256="89a4c1e1e45e0b23dffe708202cb2eaffde0fe3727d7692b2e1739fec78a7dac"

echo "================================================"
echo "Building QEMU with Cosmopolitan libc"
echo "Host architectures: ${ARCHES}"
echo "System emulators:   ${SYSTEM_TARGETS:-(none)}"
echo "================================================"
echo "Build directory: ${BUILD_DIR}"
echo "QEMU version: ${QEMU_VERSION}"
echo "glib version: ${GLIB_VERSION}"
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() { echo "Error: $*" >&2; exit 1; }

# run_logged <name> <command...>: run quietly, dump the log tail on failure
run_logged() {
    local name=$1; shift
    local log="${LOG_DIR}/${name}.log"
    echo "  ${name}..."
    if ! "$@" >"${log}" 2>&1; then
        echo "Error: step '${name}' failed. Last lines of ${log}:" >&2
        tail -n 40 "${log}" >&2
        exit 1
    fi
}

# download <sha256> <output name> <url>...: try each URL until one matches
download() {
    local sha=$1 name=$2; shift 2
    local out="${DL_DIR}/${name}" url
    if [ -f "$out" ] && echo "${sha}  ${out}" | sha256sum -c --status; then
        return 0
    fi
    for url in "$@"; do
        echo "  downloading ${name} from ${url}"
        if curl --retry 5 --retry-delay 5 -sSfL -o "$out" "$url" \
            && echo "${sha}  ${out}" | sha256sum -c --status; then
            return 0
        fi
        echo "  (failed or checksum mismatch, trying next mirror)"
    done
    die "could not download ${name} with a matching checksum"
}

# clone_tag <repo> <tag> <dest>
clone_tag() {
    echo "  cloning $(basename "$1" .git) $2"
    GIT_LFS_SKIP_SMUDGE=1 git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "$1" "$3"
    [ -d "$3/.git" ] || die "clone of $1 failed"
}

# apply_patches <component> <version> <source dir>
apply_patches() {
    local dir="${PROJECT_ROOT}/patches/$1/$2"
    [ -d "$dir" ] || return 0
    local p
    for p in "$dir"/*.patch; do
        [ -f "$p" ] || continue
        echo "  applying $1/$(basename "$p")"
        patch -s -p1 -d "$3" < "$p"
    done
}

# ---------------------------------------------------------------------------
# Tool checks
# ---------------------------------------------------------------------------

for tool in cosmocc apelink assimilate fixupobj git curl make patch zip bzip2 ninja python3 meson pkg-config sha256sum; do
    command -v "$tool" &>/dev/null || die "$tool not found in PATH
For cosmocc see https://cosmo.zip/pub/cosmocc/ (or a jart/cosmopolitan GitHub release)"
done
for arch in $ARCHES; do
    command -v "${arch}-unknown-cosmo-cc" &>/dev/null || die "${arch}-unknown-cosmo-cc not found in PATH"
done
for guest in $SYSTEM_TARGETS; do
    case "$guest" in
        x86_64|aarch64) ;;
        *) die "unsupported system emulator target '${guest}' (supported: x86_64 aarch64)" ;;
    esac
done

COSMO_BIN="$(cd "$(dirname "$(command -v cosmocc)")" && pwd)"

echo "Found toolchain:"
echo "  cosmocc: $(command -v cosmocc)"
echo "  apelink: $(command -v apelink)"
echo "  meson:   $(meson --version)"
echo ""

# ---------------------------------------------------------------------------
# Prepare directories, toolchain shims and sources
# ---------------------------------------------------------------------------

rm -rf "${SRC_DIR}" "${TOOLS_DIR}" "${BUILD_DIR}"/{x86_64,aarch64} "${LOG_DIR}"
mkdir -p "${DL_DIR}" "${LOG_DIR}" "${SRC_DIR}" "${TOOLS_DIR}" "${OUTPUT_DIR}"

# cosmocc ships its binutils as APE files, which Python (meson) cannot exec
# directly, so use assimilated (native ELF) copies. The compiler wrappers also
# drop -m64, which the cosmocc driver mishandles and which QEMU's configure
# always adds on x86_64.
echo "Preparing toolchain shims..."
for arch in $ARCHES; do
    for t in ar ranlib nm strip objcopy ld as; do
        cp "${COSMO_BIN}/${arch}-linux-cosmo-${t}" "${TOOLS_DIR}/${arch}-cosmo-${t}"
        # already-native ELF files make assimilate exit nonzero; that is fine
        assimilate -x "${TOOLS_DIR}/${arch}-cosmo-${t}" >/dev/null 2>&1 || true
        "${TOOLS_DIR}/${arch}-cosmo-${t}" --version >/dev/null 2>&1 \
            || die "${arch}-cosmo-${t} is not runnable after assimilate"
    done
    for t in cc gcc; do
        cat > "${TOOLS_DIR}/${arch}-cosmo-${t}" <<EOF
#!/bin/bash
args=()
for a in "\$@"; do [[ \$a == -m64 ]] || args+=("\$a"); done
exec "${COSMO_BIN}/${arch}-unknown-cosmo-cc" "\${args[@]}"
EOF
    done
    for t in c++ g++; do
        cat > "${TOOLS_DIR}/${arch}-cosmo-${t}" <<EOF
#!/bin/bash
args=()
for a in "\$@"; do [[ \$a == -m64 ]] || args+=("\$a"); done
exec "${COSMO_BIN}/${arch}-unknown-cosmo-c++" "\${args[@]}"
EOF
    done
    ln -s "$(command -v pkg-config)" "${TOOLS_DIR}/${arch}-cosmo-pkg-config"
    chmod +x "${TOOLS_DIR}"/${arch}-cosmo-*
done
export PATH="${TOOLS_DIR}:${PATH}"

echo "Fetching sources..."
download "${ZLIB_SHA256}" "zlib-${ZLIB_VERSION}.tar.gz" "${ZLIB_URLS[@]}"
download "${PCRE2_SHA256}" "pcre2-${PCRE2_VERSION}.tar.bz2" "${PCRE2_URLS[@]}"
download "${LIBFFI_SHA256}" "libffi-${LIBFFI_VERSION}.tar.gz" "${LIBFFI_URLS[@]}"
download "${PIXMAN_SHA256}" "pixman-${PIXMAN_VERSION}.tar.gz" "${PIXMAN_URLS[@]}"
tar -xf "${DL_DIR}/zlib-${ZLIB_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/pcre2-${PCRE2_VERSION}.tar.bz2" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libffi-${LIBFFI_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/pixman-${PIXMAN_VERSION}.tar.gz" -C "${SRC_DIR}"

clone_tag "${GLIB_REPO}" "${GLIB_VERSION}" "${SRC_DIR}/glib"
clone_tag "${PROXY_LIBINTL_REPO}" "${PROXY_LIBINTL_VERSION}" "${SRC_DIR}/glib/subprojects/proxy-libintl"
clone_tag "${QEMU_REPO}" "${QEMU_VERSION}" "${SRC_DIR}/qemu"

apply_patches glib "${GLIB_VERSION}" "${SRC_DIR}/glib"
apply_patches qemu "${QEMU_VERSION}" "${SRC_DIR}/qemu"

# ---------------------------------------------------------------------------
# Per-architecture build
# ---------------------------------------------------------------------------

exe_wrapper_for() {
    local var="EXE_WRAPPER_$1"
    if [ -n "${!var:-}" ]; then
        echo "${!var}"
    elif [ "$1" = "x86_64" ]; then
        # x86_64 outputs are APE files; sh knows how to start them
        echo "sh"
    else
        echo "qemu-$1-static"
    fi
}

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
    for f in ioctl types posix_types posix_types_64 bitsperlong byteorder swab; do
        [ -f "${asm}/${f}.h" ] && cp "${asm}/${f}.h" "${S}/include/asm/"
    done
    cp -r "${root}/asm-generic/." "${S}/include/asm-generic/"
}

build_deps() {
    local arch=$1 S=$2 B=$3
    local cc="${arch}-cosmo-cc" ar="${arch}-cosmo-ar" ranlib="${arch}-cosmo-ranlib"
    local host_triplet="${arch}-linux"
    local wrapper; wrapper="$(exe_wrapper_for "$arch")"
    export CC="${cc}" AR="${ar}" RANLIB="${ranlib}"

    # zlib
    mkdir -p "${B}/zlib" && cp -r "${SRC_DIR}/zlib-${ZLIB_VERSION}/." "${B}/zlib"
    run_logged "${arch}-zlib" bash -c "cd '${B}/zlib' && ./configure --prefix='${S}' --static && make -j${JOBS} && make install"

    # pcre2
    mkdir -p "${B}/pcre2" && cd "${B}/pcre2"
    run_logged "${arch}-pcre2" bash -c "'${SRC_DIR}/pcre2-${PCRE2_VERSION}/configure' --prefix='${S}' --host=${host_triplet} --disable-shared --enable-static && make -j${JOBS} && make install"

    # libffi (static trampolines need a raw mmap of the exec file, unsupported here)
    mkdir -p "${B}/libffi" && cd "${B}/libffi"
    run_logged "${arch}-libffi" bash -c "'${SRC_DIR}/libffi-${LIBFFI_VERSION}/configure' --prefix='${S}' --host=${host_triplet} --disable-shared --enable-static --disable-exec-static-tramp && make -j${JOBS} && make install"
    unset CC AR RANLIB

    # glib: only glib, gmodule and gthread are needed by QEMU. gio does not
    # compile against cosmocc, so build those targets and stage them by hand.
    local cross="${B}/cross.txt" glibb="${B}/glib"
    local cpu_family=${arch}
    cat > "${cross}" <<EOF
[binaries]
c = '${arch}-cosmo-cc'
cpp = '${arch}-cosmo-c++'
ar = '${arch}-cosmo-ar'
ranlib = '${arch}-cosmo-ranlib'
strip = '${arch}-cosmo-strip'
pkg-config = 'pkg-config'
exe_wrapper = [$(printf "'%s'," ${wrapper} | sed 's/,$//')]

[built-in options]
pkg_config_path = '${S}/lib/pkgconfig'
c_args = ['-I${S}/include']
c_link_args = ['-L${S}/lib']

[host_machine]
system = 'linux'
cpu_family = '${cpu_family}'
cpu = '${arch}'
endian = 'little'

[properties]
needs_exe_wrapper = true
EOF
    run_logged "${arch}-glib-configure" env PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig" \
        meson setup "${glibb}" "${SRC_DIR}/glib" --cross-file "${cross}" \
        --prefix="${S}" --default-library=static --wrap-mode=nodownload \
        -Dtests=false -Dglib_debug=disabled -Dintrospection=disabled -Dnls=disabled \
        -Dselinux=disabled -Dxattr=false -Dlibmount=disabled -Dlibelf=disabled \
        -Dsysprof=disabled -Dman-pages=disabled -Ddtrace=disabled -Dsystemtap=disabled
    run_logged "${arch}-glib-build" ninja -C "${glibb}" -j"${JOBS}" \
        glib/libglib-2.0.a gmodule/libgmodule-2.0.a gthread/libgthread-2.0.a \
        subprojects/proxy-libintl/libintl.a

    echo "  staging glib into sysroot..."
    local g="${SRC_DIR}/glib" inc="${S}/include/glib-2.0"
    mkdir -p "${inc}/glib/deprecated" "${inc}/gmodule" "${S}/lib/glib-2.0/include" "${S}/lib/pkgconfig"
    cp "${glibb}/glib/libglib-2.0.a" "${glibb}/gmodule/libgmodule-2.0.a" \
       "${glibb}/gthread/libgthread-2.0.a" "${glibb}/subprojects/proxy-libintl/libintl.a" "${S}/lib/"
    cp "${g}"/glib/*.h "${glibb}"/glib/*.h "${inc}/glib/"
    cp "${g}"/glib/deprecated/*.h "${inc}/glib/deprecated/"
    cp "${g}/glib/glib.h" "${g}/glib/glib-unix.h" "${inc}/"
    cp "${glibb}/glib/glibconfig.h" "${S}/lib/glib-2.0/include/"
    cp "${g}"/gmodule/*.h "${glibb}"/gmodule/*.h "${inc}/gmodule/"
    cp "${g}/gmodule/gmodule.h" "${inc}/"
    cp "${g}/subprojects/proxy-libintl/libintl.h" "${S}/include/"
    local pc
    for pc in glib-2.0 gthread-2.0 gmodule-2.0 gmodule-no-export-2.0; do
        cp "${glibb}/meson-private/${pc}.pc" "${S}/lib/pkgconfig/"
    done

    # pixman (display and framebuffer code in the system emulators)
    if [ -n "${SYSTEM_TARGETS}" ]; then
        run_logged "${arch}-pixman-configure" env PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig" \
            meson setup "${B}/pixman" "${SRC_DIR}/pixman-${PIXMAN_VERSION}" --cross-file "${cross}" \
            --prefix="${S}" --default-library=static --wrap-mode=nodownload \
            -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled \
            -Dopenmp=disabled -Dtimers=false -Dgnuplot=false
        run_logged "${arch}-pixman-build" ninja -C "${B}/pixman" -j"${JOBS}" install
        stage_kernel_headers "${arch}" "${S}"
    fi
}

# guest_firmware_files <guest>: regex of files under share/qemu to embed
guest_firmware_regex() {
    case "$1" in
        x86_64) echo '^(bios(-256k|-microvm)?\.bin|qboot\.rom|vgabios.*\.bin|kvmvapic\.bin|linuxboot(_dma)?\.bin|multiboot(_dma)?\.bin|pvh\.bin|sgabios\.bin|efi-.*\.rom|edk2-(x86_64|i386)-.*\.fd|edk2-licenses\.txt|firmware/.*(x86_64|i386).*\.json|keymaps/.+)$' ;;
        aarch64) echo '^(vgabios.*\.bin|efi-.*\.rom|edk2-(aarch64|arm)-.*\.fd|edk2-licenses\.txt|firmware/.*(aarch64|arm).*\.json|keymaps/.+)$' ;;
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

    # Anything under the build directory is a generated file that has to be
    # built (edk2 images are decompressed, keymaps generated)
    local targets
    targets=$(awk -F'\t' -v qb="${qb}/" 'index($1, qb) == 1 { print substr($1, length(qb) + 1) }' "${list}")
    if [ -n "${targets}" ]; then
        # shellcheck disable=SC2086
        (cd "${qb}" && ninja -j"${JOBS}" ${targets}) >"${LOG_DIR}/firmware-${guest}.log" 2>&1 \
            || { tail -n 30 "${LOG_DIR}/firmware-${guest}.log" >&2; die "building firmware for ${guest} failed"; }
    fi

    rm -rf "${dest}"
    local src rel
    while IFS=$'\t' read -r src rel; do
        [ -f "${src}" ] || die "firmware file missing: ${src}"
        mkdir -p "${dest}/share/qemu/$(dirname "${rel}")"
        cp "${src}" "${dest}/share/qemu/${rel}"
    done < "${list}"
    echo "  staged $(wc -l < "${list}") firmware files for ${guest} ($(du -sh "${dest}" | cut -f1))"
}

build_qemu() {
    local arch=$1 S=$2 B=$3
    local qb="${B}/qemu"
    mkdir -p "${qb}" && cd "${qb}"

    # cosmocc's aarch64 GCC 14.1 crashes (ICE in emit_library_call_value_1)
    # compiling qemu-io-cmds.c at -O2 unless inlining of non-inline functions
    # is disabled.
    local extra_cflags="-I${S}/include"
    if [ "${arch}" = "aarch64" ]; then
        extra_cflags="${extra_cflags} -fno-inline-functions"
    fi

    # System emulators, and KVM when a guest matches this host architecture
    local system_flags kvm_flag="--disable-kvm" targets="" guest
    if [ -n "${SYSTEM_TARGETS}" ]; then
        for guest in ${SYSTEM_TARGETS}; do
            targets+="${guest}-softmmu,"
            [ "${guest}" = "${arch}" ] && kvm_flag="--enable-kvm"
        done
        system_flags=(--target-list="${targets%,}" ${kvm_flag})
    else
        system_flags=(--disable-system)
    fi

    # Notes on the flags:
    #  --prefix=/zip              data files are looked up in the embedded zip
    #  --disable-stack-protector  cosmocc constructors run before TLS is set up
    #  --with-coroutine=ucontext  the sigaltstack backend deadlocks under cosmo
    #  --disable-plugins          TCG plugins are loaded with dlopen
    #  --disable-png              never link a host libpng
    #  the rest strips everything cosmocc cannot build or QEMU does not need
    run_logged "${arch}-qemu-configure" env \
        PKG_CONFIG_PATH="${S}/lib/pkgconfig" PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig" \
        "${SRC_DIR}/qemu/configure" \
        --prefix=/zip \
        --cross-prefix="${arch}-cosmo-" --cpu="${arch}" --host-cc=cc \
        --extra-cflags="${extra_cflags}" --extra-ldflags="-L${S}/lib" \
        "${system_flags[@]}" \
        --disable-user --disable-docs --disable-guest-agent \
        --enable-tools --disable-werror \
        --disable-stack-protector --with-coroutine=ucontext \
        --disable-plugins --disable-png \
        --disable-linux-aio --disable-linux-io-uring \
        --disable-vhost-user --disable-vhost-kernel --disable-vhost-user-blk-server \
        --disable-vduse-blk-export --disable-libvduse \
        --disable-curl --disable-gnutls --disable-nettle --disable-gcrypt \
        --disable-zstd --disable-bzip2 --disable-fuse \
        --disable-seccomp --disable-attr --disable-libnfs --disable-libssh \
        --disable-rbd --disable-glusterfs --disable-capstone --disable-slirp

    # A later meson.build change makes ninja regenerate the build; without
    # this, the regenerated build would pick up host libraries.
    export PKG_CONFIG_PATH="${S}/lib/pkgconfig" PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig"
    local ninja_targets=(qemu-img)
    for guest in ${SYSTEM_TARGETS}; do
        ninja_targets+=("qemu-system-${guest}")
    done
    run_logged "${arch}-qemu-build" ninja -j"${JOBS}" "${ninja_targets[@]}"
    unset PKG_CONFIG_PATH PKG_CONFIG_LIBDIR

    [ -f qemu-img ] || die "qemu-img not found after ${arch} build"
    cp qemu-img "${B}/qemu-img.elf"
    for guest in ${SYSTEM_TARGETS}; do
        [ -f "qemu-system-${guest}" ] || die "qemu-system-${guest} not found after ${arch} build"
        cp "qemu-system-${guest}" "${B}/qemu-system-${guest}.elf"
        # the system emulators carry a .zip section that apelink wants fixed up
        fixupobj "${B}/qemu-system-${guest}.elf"
    done
    echo "  built ${B}/qemu-img.elf ${SYSTEM_TARGETS:+and ${SYSTEM_TARGETS}}"
}

FIRMWARE_DIR="${BUILD_DIR}/firmware"
firmware_done=0
for arch in $ARCHES; do
    echo ""
    echo "================================================"
    echo "Building for ${arch}"
    echo "================================================"
    B="${BUILD_DIR}/${arch}"
    S="${B}/sysroot"
    mkdir -p "${B}" "${S}"
    build_deps "${arch}" "${S}" "${B}"
    build_qemu "${arch}" "${S}" "${B}"

    # Firmware does not depend on the host architecture: take it from the
    # first build
    if [ "${firmware_done}" = 0 ] && [ -n "${SYSTEM_TARGETS}" ]; then
        echo "  staging firmware..."
        for guest in ${SYSTEM_TARGETS}; do
            stage_firmware "${guest}" "${B}/qemu" "${FIRMWARE_DIR}/${guest}"
        done
        firmware_done=1
    fi
done

# ---------------------------------------------------------------------------
# Link the per-arch binaries into one APE per program
# ---------------------------------------------------------------------------

echo ""
echo "================================================"
echo "Creating fat binaries with apelink"
echo "================================================"

# link_fat <program> <output>
link_fat() {
    local program=$1 output=$2
    local ape_args=() elfs=() arch
    for arch in $ARCHES; do
        ape_args+=(-l "${COSMO_BIN}/ape-${arch}.elf")
        elfs+=("${BUILD_DIR}/${arch}/${program}.elf")
    done
    if [[ " ${ARCHES} " == *" aarch64 "* ]]; then
        ape_args+=(-M "${COSMO_BIN}/ape-m1.c")
    fi
    apelink "${ape_args[@]}" -o "${output}" "${elfs[@]}"
    chmod +x "${output}"
}

link_fat qemu-img "${OUTPUT_BINARY}"
ls -lh "${OUTPUT_BINARY}"

if [ -n "${SYSTEM_TARGETS}" ]; then
    mkdir -p "${OUT_DIR}"
    for guest in ${SYSTEM_TARGETS}; do
        binary="${OUT_DIR}/qemu-system-${guest}.com"
        link_fat "qemu-system-${guest}" "${binary}"
        # Embed the firmware: QEMU was configured with --prefix=/zip, so it
        # looks for /zip/share/qemu/..., which Cosmopolitan serves from the
        # zip archive appended to the binary
        (cd "${FIRMWARE_DIR}/${guest}" && zip -qr "${binary}" share)
        ls -lh "${binary}"
    done
fi

# ---------------------------------------------------------------------------
# Licenses: QEMU is GPL-2.0, the static dependencies carry their own terms
# ---------------------------------------------------------------------------

write_notices() {
    local out=$1
    {
        echo "The QEMU binaries statically link the following libraries."
        echo "QEMU itself is licensed under the GPL-2.0 (see COPYING)."
        echo "Source for the binaries, including all patches, is available at"
        echo "https://github.com/bjia56/cosmo-qemu"
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
            echo "Firmware embedded in the system emulators"
            echo "================================================================"
            echo "SeaBIOS, edk2 and the other firmware and data files under share/qemu are"
            echo "built or bundled by QEMU; see edk2-licenses.txt inside the binaries and"
            echo "the QEMU source tree (pc-bios/README and each component's license)."
        fi
    } > "${out}"
}

cp "${SRC_DIR}/qemu/COPYING" "${OUTPUT_LICENSE}"
write_notices "${OUTPUT_NOTICES}"
echo "Copied licenses to ${OUTPUT_DIR}"
if [ -n "${SYSTEM_TARGETS}" ]; then
    cp "${SRC_DIR}/qemu/COPYING" "${OUT_DIR}/COPYING"
    write_notices "${OUT_DIR}/THIRD_PARTY_NOTICES.txt"
fi

# ---------------------------------------------------------------------------
# Smoke tests (x86_64 hosts only; the aarch64 halves are tested in CI)
# ---------------------------------------------------------------------------

if [[ " ${ARCHES} " == *" x86_64 "* ]] && [ "$(uname -m)" = "x86_64" ]; then
    echo ""
    echo "Testing qemu-img..."
    "${SCRIPT_DIR}/smoke_test.sh" "sh ${OUTPUT_BINARY}"
    for guest in ${SYSTEM_TARGETS}; do
        echo ""
        echo "Testing qemu-system-${guest}..."
        "${SCRIPT_DIR}/smoke_test_system.sh" "sh ${OUT_DIR}/qemu-system-${guest}.com" "${guest}"
    done
fi

echo ""
echo "================================================"
echo "Build complete!"
echo "================================================"
echo "qemu-img:  ${OUTPUT_BINARY}"
for guest in ${SYSTEM_TARGETS}; do
    echo "emulator:  ${OUT_DIR}/qemu-system-${guest}.com"
done
echo "================================================"
