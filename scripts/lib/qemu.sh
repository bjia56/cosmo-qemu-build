# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Configuring and building QEMU for one host architecture.
# Sourced by scripts/build.sh; relies on the variables it defines.

build_qemu() {
    local arch=$1 S=$2 B=$3
    local qb="${B}/qemu"
    mkdir -p "${qb}" && cd "${qb}"

    # Compile QEMU with -mcosmo (_COSMO_SOURCE), which exposes Cosmopolitan
    # extensions such as ShowCrashReports(); the two names it collides with are
    # patched in the QEMU sources. The compiler wrappers add the flag (see
    # COSMO_MCOSMO), and the variable stays exported so that the reconfigure
    # ninja runs after a meson.build change sees it too.
    export COSMO_MCOSMO=1
    local extra_cflags="-I${S}/include"
    # cosmocc's aarch64 GCC 14.1 crashes (ICE in emit_library_call_value_1)
    # compiling qemu-io-cmds.c at -O2 unless inlining of non-inline functions
    # is disabled.
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
        # WHPX (Windows Hypervisor Platform, loaded with cosmo_dlopen at run
        # time on Windows) for x86_64 guests on the x86_64 host slice
        local whpx_flag=""
        if [ "${arch}" = "x86_64" ] && [[ " ${SYSTEM_TARGETS} " == *" x86_64 "* ]]; then
            whpx_flag="--enable-whpx"
            extra_cflags="${extra_cflags} -I${S}/include/whp"
        fi
        # HVF (Hypervisor.framework, loaded with cosmo_dlopen at run time on
        # Apple Silicon) for aarch64 guests on the aarch64 host slice
        local hvf_flag=""
        if [ "${arch}" = "aarch64" ] && [[ " ${SYSTEM_TARGETS} " == *" aarch64 "* ]]; then
            hvf_flag="--enable-hvf"
            extra_cflags="${extra_cflags} -I${S}/include/hvf"
        fi
        system_flags=(--target-list="${targets%,}" --enable-slirp --enable-virtfs --enable-vnc ${kvm_flag} ${whpx_flag} ${hvf_flag})
    else
        system_flags=(--disable-system --disable-slirp --disable-virtfs --disable-vnc)
    fi

    # Notes on the flags:
    #  --prefix=/zip              data files are looked up in the embedded zip
    #  --disable-relocatable      otherwise QEMU resolves its data directory
    #                             relative to the executable, not to /zip
    #  --disable-stack-protector  cosmocc constructors run before TLS is set up
    #  --with-coroutine=ucontext  the sigaltstack backend deadlocks under cosmo
    #  --disable-plugins          TCG plugins are loaded with dlopen
    #  --enable-virtfs            9p file sharing, with the Cosmopolitan host support from
    #                             patch 15 (its extended attributes only work on Linux)
    #  --enable-vnc               the built-in VNC server (needs only pixman and zlib; no
    #                             TLS, SASL or JPEG, those libraries are not built)
    #  the rest strips everything cosmocc cannot build or QEMU does not need
    run_logged "${arch}-qemu-configure" env \
        PKG_CONFIG_PATH="${S}/lib/pkgconfig" PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig" \
        "${SRC_DIR}/qemu/configure" \
        --prefix=/zip --disable-relocatable \
        --cross-prefix="${arch}-cosmo-" --cpu="${arch}" --host-cc=cc \
        --extra-cflags="${extra_cflags}" --extra-ldflags="-L${S}/lib" \
        "${system_flags[@]}" \
        --disable-user --disable-docs --disable-guest-agent \
        --enable-tools --disable-werror \
        --disable-stack-protector --with-coroutine=ucontext \
        --disable-plugins --enable-png \
        --disable-linux-aio --disable-linux-io-uring \
        --disable-vhost-user --disable-vhost-kernel --disable-vhost-user-blk-server \
        --disable-vduse-blk-export --disable-libvduse \
        --disable-curl --disable-gnutls --enable-nettle --disable-gcrypt \
        --enable-zstd --enable-bzip2 --disable-fuse \
        --disable-seccomp --disable-attr --disable-libnfs --disable-libssh \
        --disable-rbd --disable-glusterfs --disable-capstone

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
