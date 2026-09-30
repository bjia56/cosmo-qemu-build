#!/bin/bash
# Linking the per-architecture ELF files into fat APE binaries.
# Sourced by scripts/build.sh; relies on the variables it defines.

# link_fat <program> <output>
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

# The executables use a loader of their own, so that the loader on Apple Silicon can
# sign itself with the hypervisor entitlement (compat/ape). Two lines of the shell
# script that apelink writes at the start of each file are edited, with
# replacements of the same length so that no offset in the file changes: the
# loader is stored as .q.ape-01 in ${TMPDIR:-$HOME} instead of apelink's default
# path, and a loader found in PATH is never used. The build fails if the script
# is not exactly what is expected. Change the loader's number when the loader
# changes: a stored loader is reused as is.
private_loader() {
    python3 - "$1" <<'PYEOF'
import sys
path = sys.argv[1]
edits = (
    # never use an "ape" found in PATH: replace the test (always false), so
    # the "exec ape" after it can never run
    (b'&& type ape >/dev/null 2>&1 && exec ape "$o" "$@"',
     b'&& false    >/dev/null 2>&1 && exec ape "$o" "$@"'),
    # where the loader is stored (change the number with the loader)
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

# prepare_loader_source
#
# A copy of cosmocc's macOS arm64 loader source that signs itself (compat/ape),
# which link_fat hands to apelink.
prepare_loader_source() {
    APE_M1_SOURCE="${BUILD_DIR}/ape-m1.c"
    cp "${COSMO_BIN}/ape-m1.c" "${APE_M1_SOURCE}"
    patch -s -p1 "${APE_M1_SOURCE}" < "${PROJECT_ROOT}/compat/ape/ape-m1-hypervisor.patch" \
        || die "compat/ape/ape-m1-hypervisor.patch does not apply to this cosmocc's ape-m1.c"
}
