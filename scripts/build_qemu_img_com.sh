#!/bin/bash
# Build script for creating qemu-img.com with Cosmopolitan libc
#
# This script builds qemu-img separately for x86_64 and aarch64 using the
# arch-specific Cosmopolitan compilers, then uses apelink to combine them into
# a single fat binary that runs on multiple platforms.
#
# qemu-img needs glib, which in turn needs libffi, pcre2 and a libintl, and
# zlib. None of those are provided by cosmocc, so they are built from source
# into a per-architecture static sysroot first.
#
# Requirements:
#   - cosmocc compiler toolchain (https://cosmo.zip/pub/cosmocc/)
#   - git, curl, make, patch, zip, ninja, python3, meson (>= 1.5), pkg-config
#   - qemu-aarch64-static, to run aarch64 configure-time probes
#     (or set EXE_WRAPPER_aarch64 to another wrapper)
#
# Usage:
#   ./scripts/build_qemu_img_com.sh
#
# Optional environment:
#   JOBS                 parallel build jobs (default: nproc)
#   ARCHES               space separated list (default: "x86_64 aarch64")
#   EXE_WRAPPER_<arch>   command used to run <arch> test programs
#   QEMU_REPO            QEMU git URL
#   GLIB_REPO            glib git URL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/build"
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

# QEMU version comes from the Python module so the package and the build agree
QEMU_VERSION=$(python3 -c "import sys; sys.path.insert(0, '${PROJECT_ROOT}/src'); from cosmo_qemu_img._version import QEMU_GIT_TAG; print(QEMU_GIT_TAG)")
QEMU_REPO="${QEMU_REPO:-https://gitlab.com/qemu-project/qemu.git}"

# Dependencies, built into the sysroot. Tarballs are verified by SHA-256.
GLIB_VERSION="2.82.4"
GLIB_REPO="${GLIB_REPO:-https://github.com/GNOME/glib.git}"
PROXY_LIBINTL_VERSION="0.4"
PROXY_LIBINTL_REPO="https://github.com/frida/proxy-libintl.git"

ZLIB_VERSION="1.3.1"
ZLIB_URL="https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz"
ZLIB_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"

PCRE2_VERSION="10.44"
PCRE2_URL="https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${PCRE2_VERSION}/pcre2-${PCRE2_VERSION}.tar.bz2"
PCRE2_SHA256="d34f02e113cf7193a1ebf2770d3ac527088d485d4e047ed10e5d217c6ef5de96"

LIBFFI_VERSION="3.4.6"
LIBFFI_URL="https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz"
LIBFFI_SHA256="b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e"

echo "================================================"
echo "Building qemu-img.com with Cosmopolitan libc"
echo "Architectures: ${ARCHES}"
echo "================================================"
echo "Build directory: ${BUILD_DIR}"
echo "Output: ${OUTPUT_BINARY}"
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

download() {
    local url=$1 sha=$2 out="${DL_DIR}/$(basename "$1")"
    if [ ! -f "$out" ] || ! echo "${sha}  ${out}" | sha256sum -c --status; then
        echo "  downloading $(basename "$url")"
        curl --retry 5 --retry-delay 5 -sSfL -o "$out" "$url"
    fi
    echo "${sha}  ${out}" | sha256sum -c --status \
        || die "checksum mismatch for ${out}"
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

for tool in cosmocc apelink assimilate git curl make patch zip ninja python3 meson pkg-config sha256sum; do
    command -v "$tool" &>/dev/null || die "$tool not found in PATH
For cosmocc see https://cosmo.zip/pub/cosmocc/ (or a jart/cosmopolitan GitHub release)"
done
for arch in $ARCHES; do
    command -v "${arch}-unknown-cosmo-cc" &>/dev/null || die "${arch}-unknown-cosmo-cc not found in PATH"
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
download "${ZLIB_URL}" "${ZLIB_SHA256}"
download "${PCRE2_URL}" "${PCRE2_SHA256}"
download "${LIBFFI_URL}" "${LIBFFI_SHA256}"
tar -xf "${DL_DIR}/zlib-${ZLIB_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/pcre2-${PCRE2_VERSION}.tar.bz2" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libffi-${LIBFFI_VERSION}.tar.gz" -C "${SRC_DIR}"

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

    # glib: only glib, gmodule and gthread are needed by qemu-img. gio does not
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
}

build_qemu_img() {
    local arch=$1 S=$2 B=$3
    local qb="${B}/qemu"
    mkdir -p "${qb}" && cd "${qb}"

    # Notes on the flags:
    #  --disable-stack-protector  cosmocc constructors run before TLS is set up
    #  --with-coroutine=ucontext  the sigaltstack backend deadlocks under cosmo
    #  the rest strips everything qemu-img does not need or cosmocc cannot build
    run_logged "${arch}-qemu-configure" env \
        PKG_CONFIG_PATH="${S}/lib/pkgconfig" PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig" \
        "${SRC_DIR}/qemu/configure" \
        --cross-prefix="${arch}-cosmo-" --cpu="${arch}" --host-cc=cc \
        --extra-cflags="-I${S}/include" --extra-ldflags="-L${S}/lib" \
        --disable-system --disable-user --disable-docs --disable-guest-agent \
        --enable-tools --disable-werror \
        --disable-stack-protector --with-coroutine=ucontext \
        --disable-linux-aio --disable-linux-io-uring \
        --disable-vhost-user --disable-vhost-kernel --disable-vhost-user-blk-server \
        --disable-vduse-blk-export --disable-libvduse \
        --disable-curl --disable-gnutls --disable-nettle --disable-gcrypt \
        --disable-zstd --disable-bzip2 --disable-fuse --disable-vnc \
        --disable-seccomp --disable-attr --disable-libnfs --disable-libssh \
        --disable-rbd --disable-glusterfs --disable-capstone --disable-slirp
    run_logged "${arch}-qemu-build" ninja -j"${JOBS}" qemu-img

    [ -f qemu-img ] || die "qemu-img not found after ${arch} build"
    cp qemu-img "${B}/qemu-img.elf"
    echo "  built ${B}/qemu-img.elf"
}

for arch in $ARCHES; do
    echo ""
    echo "================================================"
    echo "Building for ${arch}"
    echo "================================================"
    B="${BUILD_DIR}/${arch}"
    S="${B}/sysroot"
    mkdir -p "${B}" "${S}"
    build_deps "${arch}" "${S}" "${B}"
    build_qemu_img "${arch}" "${S}" "${B}"
done

# ---------------------------------------------------------------------------
# Link the per-arch binaries into one APE
# ---------------------------------------------------------------------------

echo ""
echo "================================================"
echo "Creating fat binary with apelink"
echo "================================================"

ape_args=()
elfs=()
for arch in $ARCHES; do
    ape_args+=(-l "${COSMO_BIN}/ape-${arch}.elf")
    elfs+=("${BUILD_DIR}/${arch}/qemu-img.elf")
done
if [[ " ${ARCHES} " == *" aarch64 "* ]]; then
    ape_args+=(-M "${COSMO_BIN}/ape-m1.c")
fi

apelink "${ape_args[@]}" -o "${OUTPUT_BINARY}" "${elfs[@]}"
chmod +x "${OUTPUT_BINARY}"
ls -lh "${OUTPUT_BINARY}"

# ---------------------------------------------------------------------------
# Licenses: QEMU is GPL-2.0, the static dependencies carry their own terms
# ---------------------------------------------------------------------------

cp "${SRC_DIR}/qemu/COPYING" "${OUTPUT_LICENSE}"
{
    echo "qemu-img.com statically links the following libraries."
    echo "QEMU itself is licensed under the GPL-2.0 (see COPYING)."
    echo "Source for the binary, including all patches, is available at"
    echo "https://github.com/bjia56/cosmo-qemu-img"
    for entry in \
        "glib ${GLIB_VERSION}|${SRC_DIR}/glib/COPYING" \
        "proxy-libintl ${PROXY_LIBINTL_VERSION}|${SRC_DIR}/glib/subprojects/proxy-libintl/COPYING" \
        "pcre2 ${PCRE2_VERSION}|${SRC_DIR}/pcre2-${PCRE2_VERSION}/LICENCE.md" \
        "libffi ${LIBFFI_VERSION}|${SRC_DIR}/libffi-${LIBFFI_VERSION}/LICENSE" \
        "zlib ${ZLIB_VERSION}|${SRC_DIR}/zlib-${ZLIB_VERSION}/LICENSE"; do
        name="${entry%%|*}"; file="${entry#*|}"
        echo ""
        echo "================================================================"
        echo "${name}"
        echo "================================================================"
        if [ -f "${file}" ]; then cat "${file}"; else echo "(license file not found: ${file##*/})"; fi
    done
} > "${OUTPUT_NOTICES}"
echo "Copied licenses to ${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Smoke test (x86_64 only; other architectures are tested in CI)
# ---------------------------------------------------------------------------

if [[ " ${ARCHES} " == *" x86_64 "* ]] && [ "$(uname -m)" = "x86_64" ]; then
    echo ""
    echo "Testing binary..."
    "${SCRIPT_DIR}/smoke_test.sh" "sh ${OUTPUT_BINARY}"
fi

echo ""
echo "================================================"
echo "Build complete!"
echo "================================================"
echo "Fat binary: ${OUTPUT_BINARY}"
echo "================================================"
