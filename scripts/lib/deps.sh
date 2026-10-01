# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Static dependencies (zlib, pcre2, nettle, bzip2, zstd, libffi, glib, pixman, libslirp) built into a per-architecture sysroot.
# Sourced by scripts/build.sh; relies on the variables it defines.

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
    local -a wrapper
    read -ra wrapper <<< "$(exe_wrapper_for "$arch")"
    export CC="${cc}" AR="${ar}" RANLIB="${ranlib}"

    # zlib
    mkdir -p "${B}/zlib" && cp -r "${SRC_DIR}/zlib-${ZLIB_VERSION}/." "${B}/zlib"
    run_logged "${arch}-zlib" bash -c "cd '${B}/zlib' && ./configure --prefix='${S}' --static && make -j${JOBS} && make install"

    # pcre2
    mkdir -p "${B}/pcre2" && cd "${B}/pcre2"
    run_logged "${arch}-pcre2" bash -c "'${SRC_DIR}/pcre2-${PCRE2_VERSION}/configure' --prefix='${S}' --host=${host_triplet} --disable-shared --enable-static && make -j${JOBS} && make install"

    # nettle: no GMP (so no hogweed), and no assembler, which cosmocc may not take
    mkdir -p "${B}/nettle" && cd "${B}/nettle"
    run_logged "${arch}-nettle" bash -c "'${SRC_DIR}/nettle-${NETTLE_VERSION}/configure' --prefix='${S}' --libdir='${S}/lib' --host=${host_triplet} --disable-shared --enable-static --disable-public-key --disable-assembler --disable-documentation --disable-openssl && make -j${JOBS} && make install"

    # bzip2 (only the library; it builds in the source tree, so use a copy)
    mkdir -p "${B}/bzip2" "${S}/include" "${S}/lib" && cp -r "${SRC_DIR}/bzip2-${BZIP2_VERSION}/." "${B}/bzip2"
    run_logged "${arch}-bzip2" bash -c "cd '${B}/bzip2' && make -j${JOBS} CC='${cc}' AR='${ar}' RANLIB='${ranlib}' libbz2.a && cp bzlib.h '${S}/include/' && cp libbz2.a '${S}/lib/'"

    # zstd (only the library; it builds in the source tree, so use a copy).
    # Its BMI2 assembly is left out: cosmocc rejects the (empty) object file.
    mkdir -p "${B}/zstd" && cp -r "${SRC_DIR}/zstd-${ZSTD_VERSION}/." "${B}/zstd"
    run_logged "${arch}-zstd" bash -c "cd '${B}/zstd/lib' && make -j${JOBS} ZSTD_NO_ASM=1 CC='${cc}' AR='${ar}' PREFIX='${S}' libzstd.a libzstd.pc && make ZSTD_NO_ASM=1 CC='${cc}' AR='${ar}' PREFIX='${S}' install-static install-pc install-includes"

    # libffi (static trampolines need a raw mmap of the exec file, unsupported here)
    # The Ubuntu orig tarball has no configure script, so generate it (in a copy,
    # since the source tree is shared by the architectures)
    mkdir -p "${B}/libffi-src" && cp -r "${SRC_DIR}/libffi-${LIBFFI_VERSION}/." "${B}/libffi-src"
    run_logged "${arch}-libffi-autoreconf" bash -c "cd '${B}/libffi-src' && autoreconf -fi"
    mkdir -p "${B}/libffi" && cd "${B}/libffi"
    run_logged "${arch}-libffi" bash -c "'${B}/libffi-src/configure' --prefix='${S}' --host=${host_triplet} --disable-shared --enable-static --disable-exec-static-tramp --disable-docs && make -j${JOBS} && make install"
    unset CC AR RANLIB

    # glib: only glib, gmodule and gthread are needed by QEMU. gio does not
    # compile against cosmocc, so build those targets and stage them by hand.
    local cross="${B}/cross.txt" glibb="${B}/glib"
    cat > "${cross}" <<EOF
[binaries]
c = '${arch}-cosmo-cc'
ar = '${arch}-cosmo-ar'
ranlib = '${arch}-cosmo-ranlib'
strip = '${arch}-cosmo-strip'
pkg-config = 'pkg-config'
exe_wrapper = [$(printf "'%s'," "${wrapper[@]}" | sed 's/,$//')]

[built-in options]
pkg_config_path = '${S}/lib/pkgconfig'
c_args = ['-I${S}/include']
c_link_args = ['-L${S}/lib']

[host_machine]
system = 'linux'
cpu_family = '${arch}'
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
        # libslirp (user-mode networking, -netdev user); needs only glib
        run_logged "${arch}-libslirp-configure" env PKG_CONFIG_LIBDIR="${S}/lib/pkgconfig" \
            meson setup "${B}/libslirp" "${SRC_DIR}/libslirp-v${LIBSLIRP_VERSION}" --cross-file "${cross}" \
            --prefix="${S}" --default-library=static --wrap-mode=nodownload
        run_logged "${arch}-libslirp-build" ninja -C "${B}/libslirp" -j"${JOBS}" install
        stage_kernel_headers "${arch}" "${S}"
        # WHPX only exists for x86_64 guests on x86_64 (Windows) hosts
        if [ "${arch}" = "x86_64" ] && [[ " ${SYSTEM_TARGETS} " == *" x86_64 "* ]]; then
            stage_whp_headers "${S}"
        fi
        # HVF only exists for aarch64 guests on aarch64 (Apple Silicon) hosts
        if [ "${arch}" = "aarch64" ] && [[ " ${SYSTEM_TARGETS} " == *" aarch64 "* ]]; then
            stage_hvf_headers "${S}"
        fi
    fi
}
