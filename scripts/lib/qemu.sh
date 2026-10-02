# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Configuring and building QEMU for one host architecture. Sourced by scripts/build.sh.

build_qemu() {
    local arch=$1 S=$2 B=$3
    local qb="${B}/qemu"
    mkdir -p "${qb}" && cd "${qb}"

    # -mcosmo is added by the compiler wrappers. It stays exported so the reconfigure
    # ninja runs after a meson.build change sees it too.
    export COSMO_MCOSMO=1
    local extra_cflags="-I${S}/include"
    # cosmocc's aarch64 GCC 14.1 ICEs (emit_library_call_value_1) on qemu-io-cmds.c at -O2 otherwise
    if [ "${arch}" = "aarch64" ]; then
        extra_cflags="${extra_cflags} -fno-inline-functions"
    fi

    local system_flags kvm_flag="--disable-kvm" targets="" guest
    if [ -n "${SYSTEM_TARGETS}" ]; then
        for guest in ${SYSTEM_TARGETS}; do
            targets+="${guest}-softmmu,"
            [ "${guest}" = "${arch}" ] && kvm_flag="--enable-kvm"
        done
        # WHPX: x86_64 guests, x86_64 slice
        local whpx_flag=""
        if [ "${arch}" = "x86_64" ] && [[ " ${SYSTEM_TARGETS} " == *" x86_64 "* ]]; then
            whpx_flag="--enable-whpx"
            extra_cflags="${extra_cflags} -I${S}/include/whp"
        fi
        # HVF: aarch64 guests, aarch64 slice
        local hvf_flag=""
        if [ "${arch}" = "aarch64" ] && [[ " ${SYSTEM_TARGETS} " == *" aarch64 "* ]]; then
            hvf_flag="--enable-hvf"
            extra_cflags="${extra_cflags} -I${S}/include/hvf"
        fi
        system_flags=(--target-list="${targets%,}" --enable-slirp --enable-virtfs --enable-vnc --enable-vnc-jpeg --enable-sdl --disable-sdl-image ${kvm_flag} ${whpx_flag} ${hvf_flag})
    else
        system_flags=(--disable-system --disable-slirp --disable-virtfs --disable-vnc --disable-vnc-jpeg --disable-sdl)
    fi

    #  --prefix=/zip, --disable-relocatable: data files come from the embedded zip, not relative to the executable
    #  --disable-stack-protector: cosmocc constructors run before TLS is set up
    #  --with-coroutine=ucontext: the sigaltstack backend deadlocks under cosmo
    #  --disable-plugins: TCG plugins need dlopen
    #  --enable-gnutls --enable-nettle: crypto stays on nettle; gnutls only does TLS
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
        --disable-curl --enable-gnutls --enable-nettle --disable-gcrypt \
        --enable-zstd --enable-bzip2 --disable-fuse \
        --disable-seccomp --disable-attr --disable-libnfs --disable-libssh \
        --disable-rbd --disable-glusterfs --disable-capstone

    # keep set: ninja's regeneration after a meson.build change would otherwise pick up host libraries
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
        # the .zip section needs fixing up for apelink
        fixupobj "${B}/qemu-system-${guest}.elf"
    done
    echo "  built ${B}/qemu-img.elf ${SYSTEM_TARGETS:+and ${SYSTEM_TARGETS}}"
}
