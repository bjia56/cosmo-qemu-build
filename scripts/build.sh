#!/bin/bash
# SPDX-License-Identifier: MIT
# Builds qemu-img and the QEMU system emulators for x86_64 and aarch64 with Cosmopolitan
# libc and joins both architectures into one fat APE per program (apelink).
# Outputs: out/qemu-img.com and out/qemu-system-<guest>.com (firmware embedded in /zip).
# Dependencies cosmocc lacks (glib, pixman, ...) are built into a per-architecture sysroot first.
#
# Requirements (a Linux build host with bash 4 or later):
#   - cosmocc compiler toolchain (https://cosmo.zip/pub/cosmocc/), tested with
#     4.0.2; the macOS loader patch (compat/ape) is written for that release
#   - git, curl, tar, sed, make, patch, zip, bzip2, ninja, python3, sha256sum, gperf,
#     meson (>= 1.5), pkg-config
#   - qemu-aarch64-static for aarch64 configure-time probes (or EXE_WRAPPER_aarch64)
#   - Linux kernel headers per host architecture (for KVM): linux-libc-dev and
#     linux-libc-dev-arm64-cross, or KERNEL_HEADERS_<arch> pointing at a directory
#     with linux/, asm/ and asm-generic/
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

# The steps live in scripts/lib/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-${PROJECT_ROOT}/build}"
OUT_DIR="${OUT_DIR:-${PROJECT_ROOT}/out}"
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

# Small libraries: the Ubuntu archive's "orig" tarballs, verified by SHA-256 (no fallback mirror).
UBUNTU_POOL="${UBUNTU_POOL:-https://archive.ubuntu.com/ubuntu/pool/main}"

# Ubuntu repacks zlib; the tarball unpacks to zlib-<ZLIB_ORIG_VERSION>
ZLIB_VERSION="1.3.2"
ZLIB_ORIG_VERSION="1.3.dfsg+really${ZLIB_VERSION}"
ZLIB_URL="${UBUNTU_POOL}/z/zlib/zlib_${ZLIB_ORIG_VERSION}.orig.tar.gz"
ZLIB_SHA256="7b6903eb019983987b7112eccf90f1703f1c6c0e0cede36564bf611d19ca579d"

PCRE2_VERSION="10.46"
PCRE2_URL="${UBUNTU_POOL}/p/pcre2/pcre2_${PCRE2_VERSION}.orig.tar.gz"
PCRE2_SHA256="8d28d7f2c3b970c3a4bf3776bcbb5adfc923183ce74bc8df1ebaad8c1985bd07"

# The orig tarball is a source snapshot without a configure script (see build_deps)
LIBFFI_VERSION="3.8.0"
LIBFFI_URL="${UBUNTU_POOL}/libf/libffi/libffi_${LIBFFI_VERSION}.orig.tar.gz"
LIBFFI_SHA256="bf40d752d8f5fd4505bcd1c7d4208ea87fd12c91f087e359651c776748352dc0"

LIBPNG_VERSION="1.6.58"
LIBPNG_URL="${UBUNTU_POOL}/libp/libpng1.6/libpng1.6_${LIBPNG_VERSION}.orig.tar.gz"
LIBPNG_SHA256="a9d4df463d36a6e5f9c29bd6f4967312d17e996c1854f3511f833924eb1993cf"

NETTLE_VERSION="3.10.2"
NETTLE_URL="${UBUNTU_POOL}/n/nettle/nettle_${NETTLE_VERSION}.orig.tar.gz"
NETTLE_SHA256="fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5"

BZIP2_VERSION="1.0.8"
BZIP2_URL="${UBUNTU_POOL}/b/bzip2/bzip2_${BZIP2_VERSION}.orig.tar.gz"
BZIP2_SHA256="ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269"

ZSTD_VERSION="1.5.7"
ZSTD_URL="${UBUNTU_POOL}/libz/libzstd/libzstd_${ZSTD_VERSION}+dfsg.orig.tar.xz"
ZSTD_SHA256="0c092ef267edce57ba7f3f2645c861f72eaf5e76273c6c3632869423464b90a5"

PIXMAN_VERSION="0.46.4"
PIXMAN_URL="${UBUNTU_POOL}/p/pixman/pixman_${PIXMAN_VERSION}.orig.tar.gz"
PIXMAN_SHA256="d09c44ebc3bd5bee7021c79f922fe8fb2fb57f7320f55e97ff9914d2346a591c"

# libjpeg-turbo (the lossy JPEG encoding of the VNC server), built without SIMD
LIBJPEG_TURBO_VERSION="3.1.3"
LIBJPEG_TURBO_URL="${UBUNTU_POOL}/libj/libjpeg-turbo/libjpeg-turbo_${LIBJPEG_TURBO_VERSION}.orig.tar.gz"
LIBJPEG_TURBO_SHA256="3a13a5ba767dc8264bc40b185e41368a80d5d5f945944d1dbaa4b2fb0099f4e5"

# gnutls (TLS for VNC, NBD, chardev sockets and migration); it bundles libtasn1 and libunistring
GNUTLS_VERSION="3.8.13"
GNUTLS_URL="${UBUNTU_POOL}/g/gnutls28/gnutls28_${GNUTLS_VERSION}.orig.tar.xz"
GNUTLS_SHA256="ffed8ec1bf09c2426d4f14aae377de4753b53e537d685e604e99a8b16ca9c97e"

# SDL2 headers only (-display sdl): the library itself is the host's, loaded at run time
SDL2_VERSION="2.32.10"
SDL2_URL="${UBUNTU_POOL}/libs/libsdl2/libsdl2_${SDL2_VERSION}+dfsg.orig.tar.gz"
SDL2_SHA256="31bac5add36f98b55e3fcf4456f0dab50a06cf06bbcde283be567f64b05b95f3"

# Official SDL2 release libraries (Windows x64, macOS universal) embedded for -display sdl; archive and library both pinned.
SDL2_RELEASE_URL="https://github.com/libsdl-org/SDL/releases/download/release-${SDL2_VERSION}"
SDL2_WIN_ZIP_SHA256="6cf9706eefd0a4a06dc764007934d428afaf029fabdd408a9e646048c91e18fb"
SDL2_WIN_DLL_SHA256="b37740a72a7a9706216df9f0134894bb7a850b356fd149398c67d874cbcfacb4"
SDL2_MAC_DMG_SHA256="4a7ac31640d70214e848f994be8a12849c0f97918a7e6c2e27a40036166d1a7f"
SDL2_MAC_DYLIB_SHA256="bc96277325b2e1dc75a13cf70f5ddcf63005d29e93f54a8b7adc7f5c3c017b91"

# libslirp unpacks to libslirp-v<version>
LIBSLIRP_VERSION="4.9.3"
LIBSLIRP_URL="${UBUNTU_POOL}/libs/libslirp/libslirp_${LIBSLIRP_VERSION}.orig.tar.bz2"
LIBSLIRP_SHA256="c82e22c73bdc3f2c038e538d4f0c9c2166defb2402212d61bb7cb1b530ba952f"

# libseccomp (-sandbox on): the GitHub release tarball
LIBSECCOMP_VERSION="2.6.0"
LIBSECCOMP_URL="https://github.com/seccomp/libseccomp/releases/download/v${LIBSECCOMP_VERSION}/libseccomp-${LIBSECCOMP_VERSION}.tar.gz"
LIBSECCOMP_SHA256="83b6085232d1588c379dc9b9cae47bb37407cf262e6e74993c61ba72d2a784dc"

# Cosmopolitan's license, for the notices
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

for tool in cosmocc apelink assimilate fixupobj git curl tar sed make patch zip unzip bzip2 ninja python3 meson pkg-config sha256sum autoreconf xz cmake gperf; do
    command -v "$tool" &>/dev/null || die "$tool not found in PATH
For cosmocc see https://cosmo.zip/pub/cosmocc/ (or a jart/cosmopolitan GitHub release)"
done
SEVENZIP=""
for cand in 7z 7zz 7za; do command -v "$cand" &>/dev/null && SEVENZIP="$cand" && break; done
[ -n "${SEVENZIP}" ] || [ -z "${SYSTEM_TARGETS}" ] || die "7z (p7zip-full) not found in PATH; it unpacks the macOS SDL2 library from its disk image"
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

rm -rf "${SRC_DIR}" "${TOOLS_DIR}" "${LOG_DIR}"
for arch in ${ARCHES}; do rm -rf "${BUILD_DIR:?}/${arch}"; done
mkdir -p "${DL_DIR}" "${LOG_DIR}" "${SRC_DIR}" "${TOOLS_DIR}" "${OUT_DIR}"

prepare_toolchain

echo "Fetching sources..."
download "${ZLIB_SHA256}" "zlib-${ZLIB_VERSION}.tar.gz" "${ZLIB_URL}"
download "${PCRE2_SHA256}" "pcre2-${PCRE2_VERSION}.tar.gz" "${PCRE2_URL}"
download "${LIBFFI_SHA256}" "libffi-${LIBFFI_VERSION}.tar.gz" "${LIBFFI_URL}"
download "${LIBPNG_SHA256}" "libpng-${LIBPNG_VERSION}.tar.gz" "${LIBPNG_URL}"
download "${NETTLE_SHA256}" "nettle-${NETTLE_VERSION}.tar.gz" "${NETTLE_URL}"
download "${BZIP2_SHA256}" "bzip2-${BZIP2_VERSION}.tar.gz" "${BZIP2_URL}"
download "${ZSTD_SHA256}" "zstd-${ZSTD_VERSION}.tar.xz" "${ZSTD_URL}"
download "${PIXMAN_SHA256}" "pixman-${PIXMAN_VERSION}.tar.gz" "${PIXMAN_URL}"
download "${LIBJPEG_TURBO_SHA256}" "libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz" "${LIBJPEG_TURBO_URL}"
download "${GNUTLS_SHA256}" "gnutls-${GNUTLS_VERSION}.tar.xz" "${GNUTLS_URL}"
download "${SDL2_SHA256}" "sdl2-${SDL2_VERSION}.tar.gz" "${SDL2_URL}"
download "${LIBSLIRP_SHA256}" "libslirp-${LIBSLIRP_VERSION}.tar.bz2" "${LIBSLIRP_URL}"
download "${LIBSECCOMP_SHA256}" "libseccomp-${LIBSECCOMP_VERSION}.tar.gz" "${LIBSECCOMP_URL}"
download "${COSMOPOLITAN_LICENSE_SHA256}" "cosmopolitan-LICENSE" "${COSMOPOLITAN_LICENSE_URL}"
mkdir "${SRC_DIR}/zlib-${ZLIB_VERSION}"
tar -xf "${DL_DIR}/zlib-${ZLIB_VERSION}.tar.gz" -C "${SRC_DIR}/zlib-${ZLIB_VERSION}" --strip-components=1
tar -xf "${DL_DIR}/pcre2-${PCRE2_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libffi-${LIBFFI_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libpng-${LIBPNG_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/nettle-${NETTLE_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/bzip2-${BZIP2_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/zstd-${ZSTD_VERSION}.tar.xz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/pixman-${PIXMAN_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libjpeg-turbo-${LIBJPEG_TURBO_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/gnutls-${GNUTLS_VERSION}.tar.xz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/sdl2-${SDL2_VERSION}.tar.gz" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libslirp-${LIBSLIRP_VERSION}.tar.bz2" -C "${SRC_DIR}"
tar -xf "${DL_DIR}/libseccomp-${LIBSECCOMP_VERSION}.tar.gz" -C "${SRC_DIR}"

# Fail early for a QEMU version that has no patches
[ -d "${PROJECT_ROOT}/patches/qemu/${QEMU_VERSION}" ] \
    || die "QEMU ${QEMU_VERSION} is not supported (available: $(ls "${PROJECT_ROOT}/patches/qemu" | tr '\n' ' '))"

clone_tag "${GLIB_REPO}" "${GLIB_VERSION}" "${SRC_DIR}/glib" "${GLIB_COMMIT}"
clone_tag "${PROXY_LIBINTL_REPO}" "${PROXY_LIBINTL_VERSION}" "${SRC_DIR}/glib/subprojects/proxy-libintl" "${PROXY_LIBINTL_COMMIT}"
clone_tag "${QEMU_REPO}" "${QEMU_VERSION}" "${SRC_DIR}/qemu" "${QEMU_COMMIT}"

apply_patches glib "${GLIB_VERSION}" "${SRC_DIR}/glib"
apply_patches libslirp "${LIBSLIRP_VERSION}" "${SRC_DIR}/libslirp-v${LIBSLIRP_VERSION}"
apply_patches libseccomp "${LIBSECCOMP_VERSION}" "${SRC_DIR}/libseccomp-${LIBSECCOMP_VERSION}"
apply_patches qemu "${QEMU_VERSION}" "${SRC_DIR}/qemu"
stage_scanf_shim
stage_seccomp_shim

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

    # firmware is architecture-independent: take it from the first build
    if [ "${firmware_done}" = 0 ] && [ -n "${SYSTEM_TARGETS}" ]; then
        echo "  staging firmware..."
        for guest in ${SYSTEM_TARGETS}; do
            stage_firmware "${guest}" "${B}/qemu" "${FIRMWARE_DIR}/${guest}"
        done
        firmware_done=1
    fi
done

echo ""
echo "================================================"
echo "Creating fat binaries with apelink"
echo "================================================"

prepare_loader_source
SDL2_LIB_DIR="${BUILD_DIR}/sdl2-libs"
[ -z "${SYSTEM_TARGETS}" ] || stage_sdl2_libraries "${SDL2_LIB_DIR}"

prepare_licenses

link_fat qemu-img "${OUT_DIR}/qemu-img.com"
embed_licenses "${OUT_DIR}/qemu-img.com"
ls -lh "${OUT_DIR}/qemu-img.com"

if [ -n "${SYSTEM_TARGETS}" ]; then
    for guest in ${SYSTEM_TARGETS}; do
        binary="${OUT_DIR}/qemu-system-${guest}.com"
        link_fat "qemu-system-${guest}" "${binary}"
        # QEMU is configured with --prefix=/zip, so it finds its firmware in the appended zip
        (cd "${FIRMWARE_DIR}/${guest}" && zip -qr "${binary}" share)
        (cd "${SDL2_LIB_DIR}" && zip -qr "${binary}" share)
        embed_licenses "${binary}"
        ls -lh "${binary}"
    done
fi

# Smoke tests on x86_64 hosts only; CI runs the aarch64 halves
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
