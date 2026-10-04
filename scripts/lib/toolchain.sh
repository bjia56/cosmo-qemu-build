# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Toolchain shims under the names QEMU's configure and meson expect (<arch>-cosmo-<tool>).
# Sourced by scripts/build.sh.

# cosmocc's binutils are APE files, which Python (meson) cannot exec, so use
# assimilated (native ELF) copies. The compiler wrappers drop -m64, which the
# cosmocc driver mishandles and QEMU's configure always adds on x86_64.
prepare_toolchain() {
    local arch t
    echo "Preparing toolchain shims..."
    for arch in $ARCHES; do
        for t in ar ranlib nm strip objcopy ld as; do
            cp "${COSMO_BIN}/${arch}-linux-cosmo-${t}" "${TOOLS_DIR}/${arch}-cosmo-${t}"
            # exits nonzero on files that are already ELF
            assimilate -x "${TOOLS_DIR}/${arch}-cosmo-${t}" >/dev/null 2>&1 || true
            "${TOOLS_DIR}/${arch}-cosmo-${t}" --version >/dev/null 2>&1 \
                || die "${arch}-cosmo-${t} is not runnable after assimilate"
        done
        # the canary itself must not be protected, so use the driver directly
        "${COSMO_BIN}/${arch}-unknown-cosmo-cc" -O2 -fno-stack-protector \
            -c "${PROJECT_ROOT}/compat/ssp/cosmo-ssp.c" -o "${TOOLS_DIR}/${arch}-cosmo-ssp.o" \
            || die "could not build the ${arch} stack protector guard"
        for t in cc gcc; do
            cat > "${TOOLS_DIR}/${arch}-cosmo-${t}" <<WRAPPER
#!/bin/bash
args=()
for a in "\$@"; do [[ \$a == -m64 ]] || args+=("\$a"); done
# -mcosmo must be on the driver's command line (QEMU's link step uses a response
# file, where it is not seen); skip "--version" style probes.
if [[ -n \${COSMO_MCOSMO:-} ]]; then
    for a in "\${args[@]}"; do
        case \$a in -c|-o|-E|-S) args=(-mcosmo "\${args[@]}"); break ;; esac
    done
fi
# Stack protector for QEMU and every dependency (see compat/ssp): a global canary, and the
# object that defines it on every link.
probe=
link=
for a in "\${args[@]}"; do
    case \$a in
        --version|-v|--help|-dump*|-print-*) probe=1 ;;
        -c|-S|-E|-M|-MM) link=; break ;;
        # QEMU's link step passes its arguments (including -o) in a response file
        -o|@*) link=1 ;;
    esac
done
if [[ -z \$probe ]]; then
    args=(-fstack-protector-strong -mstack-protector-guard=global "\${args[@]}")
    [[ -n \$link ]] && args+=("${TOOLS_DIR}/${arch}-cosmo-ssp.o")
fi
exec "${COSMO_BIN}/${arch}-unknown-cosmo-cc" "\${args[@]}"
WRAPPER
        done
        # link pkg-config after chmod, which would follow the symlink
        chmod +x "${TOOLS_DIR}"/${arch}-cosmo-*
        ln -sf "$(command -v pkg-config)" "${TOOLS_DIR}/${arch}-cosmo-pkg-config"
    done
    export PATH="${TOOLS_DIR}:${PATH}"
}
