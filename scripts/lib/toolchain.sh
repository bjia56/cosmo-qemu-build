# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Toolchain shims: native copies of cosmocc's binutils and compiler wrappers under
# the names QEMU's configure and meson expect (<arch>-cosmo-<tool>).
# Sourced by scripts/build.sh; relies on the variables it defines.

# prepare_toolchain
#
# cosmocc ships its binutils as APE files, which Python (meson) cannot exec
# directly, so use assimilated (native ELF) copies. The compiler wrappers also
# drop -m64, which the cosmocc driver mishandles and which QEMU's configure
# always adds on x86_64.
prepare_toolchain() {
    local arch t
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
            cat > "${TOOLS_DIR}/${arch}-cosmo-${t}" <<WRAPPER
#!/bin/bash
args=()
for a in "\$@"; do [[ \$a == -m64 ]] || args+=("\$a"); done
# -mcosmo has to be seen by the cosmocc driver itself; QEMU's link step passes
# its flags in a response file, where the driver cannot see them. Only add it to
# real compile/link/preprocess invocations, not to "--version" style probes.
if [[ -n \${COSMO_MCOSMO:-} ]]; then
    for a in "\${args[@]}"; do
        case \$a in -c|-o|-E|-S) args=(-mcosmo "\${args[@]}"); break ;; esac
    done
fi
exec "${COSMO_BIN}/${arch}-unknown-cosmo-cc" "\${args[@]}"
WRAPPER
        done
        # chmod follows symlinks and would fail on the system pkg-config, so link it after
        chmod +x "${TOOLS_DIR}"/${arch}-cosmo-*
        ln -sf "$(command -v pkg-config)" "${TOOLS_DIR}/${arch}-cosmo-pkg-config"
    done
    export PATH="${TOOLS_DIR}:${PATH}"
}
