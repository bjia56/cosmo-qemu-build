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
#   - the mingw-w64 headers (mingw-w64-common on Debian/Ubuntu), for QEMU's WHPX
#     code (or point WHP_HEADERS at a directory containing winhvplatform.h)
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

# The steps live in scripts/lib/: common (helpers), toolchain, headers, deps,
# firmware, qemu, link and notices. This file holds the configuration and runs
# them in order.

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

for f in common toolchain headers deps firmware qemu link notices; do
    # shellcheck disable=SC1090
    . "${SCRIPT_DIR}/lib/${f}.sh"
done

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

prepare_toolchain

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
    unset COSMO_MCOSMO

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

prepare_loader_source

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
