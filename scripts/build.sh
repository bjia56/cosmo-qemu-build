#!/bin/bash
# SPDX-License-Identifier: MIT
# Build script for qemu-img and the QEMU system emulators with Cosmopolitan libc
#
# This script builds QEMU separately for x86_64 and aarch64 hosts using the
# arch-specific Cosmopolitan compilers, then uses apelink to combine the two
# into a single fat binary per program that runs on multiple platforms.
#
# Outputs:
#   out/qemu-img.com                         qemu-img
#   out/qemu-system-<guest>.com              one system emulator per guest
#                                            architecture, with its firmware
#                                            embedded in /zip; KVM is compiled
#                                            in where the guest matches the host
#                                            architecture, WHPX (x86_64) and HVF
#                                            (aarch64) for Windows and Apple
#                                            Silicon, and TCG everywhere
#
# COPYING and THIRD_PARTY_NOTICES.txt are embedded in each executable's zip
# archive (unzip -p qemu-img.com COPYING).
#
# The emulators pick an accelerator at run time (-machine accel=kvm:tcg): KVM
# only works on Linux hosts where /dev/kvm is usable and the guest architecture
# matches the host's, WHPX on Windows with the Hypervisor Platform enabled, HVF
# on Apple Silicon; otherwise QEMU falls back to TCG.
#
# QEMU needs glib (which needs libffi, pcre2 and a libintl), pixman and zlib.
# None of those are provided by cosmocc, so they are built from source into a
# per-architecture static sysroot first.
#
# Requirements (a Linux build host with bash 4 or later):
#   - cosmocc compiler toolchain (https://cosmo.zip/pub/cosmocc/), tested with
#     4.0.2; the macOS loader patch (compat/ape) is written for that release
#   - git, curl, tar, sed, make, patch, zip, bzip2, ninja, python3, sha256sum,
#     meson (>= 1.5), pkg-config
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
#   OUT_DIR              output location (default: ./out)
#   EXE_WRAPPER_<arch>   command used to run <arch> test programs
#   KERNEL_HEADERS_<arch> kernel header tree for <arch>
#   QEMU_VERSION         QEMU tag to build; only versions with a directory in
#                        patches/qemu/ are supported (default: v9.2.0)
#   QEMU_REPO            QEMU git URL
#   GLIB_REPO            glib git URL
#   WHP_HEADERS_URL      where the Windows Hypervisor Platform headers are fetched
#   (BUILD_DIR and OUT_DIR may be relative; they are made absolute)

# The steps live in scripts/lib/: common (helpers), toolchain, headers, deps,
# firmware, qemu, link and notices. This file holds the configuration and runs
# them in order.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/out}"
# the build changes directories a lot, so work with absolute paths
mkdir -p "${BUILD_DIR}" "${OUT_DIR}"
BUILD_DIR="$(cd "${BUILD_DIR}" && pwd)"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"
DL_DIR="${BUILD_DIR}/dl"
LOG_DIR="${BUILD_DIR}/logs"
SRC_DIR="${BUILD_DIR}/source"
TOOLS_DIR="${BUILD_DIR}/tools"

JOBS="${JOBS:-$(nproc)}"
ARCHES="${ARCHES:-x86_64 aarch64}"
SYSTEM_TARGETS="${SYSTEM_TARGETS-x86_64 aarch64}"

# The QEMU release to build: a tag from https://gitlab.com/qemu-project/qemu/-/tags
# (patches/qemu/<tag> holds the changes for it)
QEMU_VERSION="${QEMU_VERSION:-v9.2.0}"
# Commits the tags resolve to (update together with the versions)
QEMU_COMMIT="ae35f033b874c627d81d51070187fbf55f0bf1a7"
QEMU_REPO="${QEMU_REPO:-https://gitlab.com/qemu-project/qemu.git}"

# Dependencies, built into the sysroot. Tarballs are verified by SHA-256.
GLIB_VERSION="2.82.4"
GLIB_COMMIT="ca20e4ac71864f08e980dc044ac96c06d5482b37"
GLIB_REPO="${GLIB_REPO:-https://github.com/GNOME/glib.git}"
PROXY_LIBINTL_VERSION="0.4"
PROXY_LIBINTL_COMMIT="c03e1a74b17fa7ec467e110130775409e4828a4c"
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
    "https://archive.ubuntu.com/ubuntu/pool/main/p/pixman/pixman_${PIXMAN_VERSION}.orig.tar.gz"
    "https://cairographics.org/releases/pixman-${PIXMAN_VERSION}.tar.gz"
)
PIXMAN_SHA256="89a4c1e1e45e0b23dffe708202cb2eaffde0fe3727d7692b2e1739fec78a7dac"

# libslirp (user-mode networking); the tarball unpacks to libslirp-v<version>
LIBSLIRP_VERSION="4.9.1"
LIBSLIRP_URLS=("https://archive.ubuntu.com/ubuntu/pool/main/libs/libslirp/libslirp_${LIBSLIRP_VERSION}.orig.tar.bz2")
LIBSLIRP_SHA256="3caff6e2de445f4995629d4929c55419f661b2b1d14f12481e155a71c1e8f811"

# Cosmopolitan Libc's license, for the notices (the libc is linked into every executable)
COSMOPOLITAN_VERSION="4.0.2"
COSMOPOLITAN_LICENSE_URL="https://raw.githubusercontent.com/jart/cosmopolitan/${COSMOPOLITAN_VERSION}/LICENSE"
COSMOPOLITAN_LICENSE_SHA256="188101f17152d898b65719a4c4fc501aa71c16649cc37ebab534bcb3511c6127"

# Windows Hypervisor Platform headers, MIT-licensed by Microsoft (see stage_whp_headers)
WHP_HEADERS_COMMIT="aaa369489dc90c6483748af94c20897f12ae77dc"
WHP_HEADERS_URL="https://raw.githubusercontent.com/MicrosoftDocs/Virtualization-Documentation/${WHP_HEADERS_COMMIT}/virtualization/api/hypervisor-platform/headers"
declare -A WHP_HEADER_SHA256=(
    [WinHvPlatform.h]="b97678400db4123faa87d1909e30f795dacaeec3e0c408ef66f5f9633412af93"
    [WinHvPlatformDefs.h]="479b247b2782ab3e7fe657d438b379fdc58df64bebeafbe6aee0386c99e0df1d"
    [WinHvEmulation.h]="5d303c96e2063520d056c6856ee401054c7689859fb6f1c624481c141dc71333"
)

for f in common toolchain headers deps firmware qemu link notices; do
    # shellcheck source=/dev/null
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

for tool in cosmocc apelink assimilate fixupobj git curl tar sed make patch zip bzip2 ninja python3 meson pkg-config sha256sum; do
    command -v "$tool" &>/dev/null || die "$tool not found in PATH
For cosmocc see https://cosmo.zip/pub/cosmocc/ (or a jart/cosmopolitan GitHub release)"
done
for arch in $ARCHES; do
    command -v "${arch}-unknown-cosmo-cc" &>/dev/null || die "${arch}-unknown-cosmo-cc not found in PATH"
done
if [[ " ${ARCHES} " == *" aarch64 "* ]] && [ -z "${EXE_WRAPPER_aarch64:-}" ]; then
    command -v qemu-aarch64-static &>/dev/null \
        || die "qemu-aarch64-static not found in PATH (it runs the aarch64 configure-time probes;
or set EXE_WRAPPER_aarch64 to another wrapper)"
fi
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

rm -rf "${SRC_DIR}" "${TOOLS_DIR}" "${LOG_DIR}"
for arch in ${ARCHES}; do rm -rf "${BUILD_DIR:?}/${arch}"; done
mkdir -p "${DL_DIR}" "${LOG_DIR}" "${SRC_DIR}" "${TOOLS_DIR}" "${OUT_DIR}"

prepare_toolchain

echo "Fetching sources..."
download "${ZLIB_SHA256}" "zlib-${ZLIB_VERSION}.tar.gz" "${ZLIB_URLS[@]}"
download "${PCRE2_SHA256}" "pcre2-${PCRE2_VERSION}.tar.bz2" "${PCRE2_URLS[@]}"
download "${LIBFFI_SHA256}" "libffi-${LIBFFI_VERSION}.tar.gz" "${LIBFFI_URLS[@]}"
download "${PIXMAN_SHA256}" "pixman-${PIXMAN_VERSION}.tar.gz" "${PIXMAN_URLS[@]}"
download "${LIBSLIRP_SHA256}" "libslirp-${LIBSLIRP_VERSION}.tar.bz2" "${LIBSLIRP_URLS[@]}"
download "${COSMOPOLITAN_LICENSE_SHA256}" "cosmopolitan-LICENSE" "${COSMOPOLITAN_LICENSE_URL}"
tar -xf "${DL_DIR}/zlib-${ZLIB_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/pcre2-${PCRE2_VERSION}.tar.bz2" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libffi-${LIBFFI_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/pixman-${PIXMAN_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libslirp-${LIBSLIRP_VERSION}.tar.bz2" -C "${SRC_DIR}"

# Fail early for a QEMU version that has no patches
[ -d "${PROJECT_ROOT}/patches/qemu/${QEMU_VERSION}" ] \
    || die "QEMU ${QEMU_VERSION} is not supported (available: $(ls "${PROJECT_ROOT}/patches/qemu" | tr '\n' ' '))"

clone_tag "${GLIB_REPO}" "${GLIB_VERSION}" "${SRC_DIR}/glib" "${GLIB_COMMIT}"
clone_tag "${PROXY_LIBINTL_REPO}" "${PROXY_LIBINTL_VERSION}" "${SRC_DIR}/glib/subprojects/proxy-libintl" "${PROXY_LIBINTL_COMMIT}"
clone_tag "${QEMU_REPO}" "${QEMU_VERSION}" "${SRC_DIR}/qemu" "${QEMU_COMMIT}"

apply_patches glib "${GLIB_VERSION}" "${SRC_DIR}/glib"
apply_patches libslirp "${LIBSLIRP_VERSION}" "${SRC_DIR}/libslirp-v${LIBSLIRP_VERSION}"
apply_patches qemu "${QEMU_VERSION}" "${SRC_DIR}/qemu"
stage_scanf_shim

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

# ---------------------------------------------------------------------------
# Licenses go into every executable (see lib/notices.sh)
# ---------------------------------------------------------------------------

prepare_licenses

link_fat qemu-img "${OUT_DIR}/qemu-img.com"
embed_licenses "${OUT_DIR}/qemu-img.com"
ls -lh "${OUT_DIR}/qemu-img.com"

if [ -n "${SYSTEM_TARGETS}" ]; then
    for guest in ${SYSTEM_TARGETS}; do
        binary="${OUT_DIR}/qemu-system-${guest}.com"
        link_fat "qemu-system-${guest}" "${binary}"
        # Embed the firmware: QEMU was configured with --prefix=/zip, so it
        # looks for /zip/share/qemu/..., which Cosmopolitan serves from the
        # zip archive appended to the binary
        (cd "${FIRMWARE_DIR}/${guest}" && zip -qr "${binary}" share)
        embed_licenses "${binary}"
        ls -lh "${binary}"
    done
fi

# ---------------------------------------------------------------------------
# Smoke tests (x86_64 hosts only; the aarch64 halves are tested in CI)
# ---------------------------------------------------------------------------

if [[ " ${ARCHES} " == *" x86_64 "* ]] && [ "$(uname -m)" = "x86_64" ]; then
    echo ""
    echo "Testing qemu-img..."
    "${SCRIPT_DIR}/smoke_test.sh" "sh ${OUT_DIR}/qemu-img.com"
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
echo "qemu-img:  ${OUT_DIR}/qemu-img.com"
for guest in ${SYSTEM_TARGETS}; do
    echo "emulator:  ${OUT_DIR}/qemu-system-${guest}.com"
done
echo "================================================"
