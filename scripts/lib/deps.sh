#!/bin/bash
# Static dependencies (zlib, pcre2, libffi, glib, pixman) built into a per-architecture sysroot.
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
