# shellcheck shell=bash
# SPDX-License-Identifier: MIT
# Linking the per-architecture ELF files into fat APE binaries. Sourced by scripts/build.sh.

link_fat() {
    local program=$1 output=$2
    local ape_args=() elfs=() arch
    for arch in $ARCHES; do
        ape_args+=(-l "${COSMO_BIN}/ape-${arch}.elf")
        elfs+=("${BUILD_DIR}/${arch}/${program}.elf")
    done
    if [[ " ${ARCHES} " == *" aarch64 "* ]]; then
        ape_args+=(-M "${APE_M1_SOURCE}")
    fi
    apelink "${ape_args[@]}" -o "${output}" "${elfs[@]}"
    chmod +x "${output}"
    private_loader "${output}"
}

# Give the executables their own loader (see compat/ape): edit two lines of apelink's
# header script with same-length replacements, so no file offset changes. The build fails
# if the script is not as expected. Bump the loader number when the loader changes, since
# a stored loader is reused as is.
private_loader() {
    python3 - "$1" <<'PYEOF'
import sys
path = sys.argv[1]
edits = (
    # never use an "ape" from PATH
    (b'&& type ape >/dev/null 2>&1 && exec ape "$o" "$@"',
     b'&& false    >/dev/null 2>&1 && exec ape "$o" "$@"'),
    # loader path
    (b't="${TMPDIR:-${HOME:-.}}/.ape-1.10"',
     b't="${TMPDIR:-${HOME:-.}}/.q.ape-01"'),
)
with open(path, "r+b") as f:
    head = bytearray(f.read(262144))
    for old, new in edits:
        assert len(old) == len(new)
        n = head.count(old)
        if n < 1 or n > 2:
            sys.exit("apelink's script header is not as expected: %r found %d times" % (old, n))
        head = head.replace(old, new)
    f.seek(0)
    f.write(head)
PYEOF
}

# Patched copy of cosmocc's macOS arm64 loader source (compat/ape) for apelink.
prepare_loader_source() {
    [[ " ${ARCHES} " == *" aarch64 "* ]] || return 0
    APE_M1_SOURCE="${BUILD_DIR}/ape-m1.c"
    cp "${COSMO_BIN}/ape-m1.c" "${APE_M1_SOURCE}"
    patch -s -p1 "${APE_M1_SOURCE}" < "${PROJECT_ROOT}/compat/ape/ape-m1-hypervisor.patch" \
        || die "compat/ape/ape-m1-hypervisor.patch does not apply to this cosmocc's ape-m1.c"
}
