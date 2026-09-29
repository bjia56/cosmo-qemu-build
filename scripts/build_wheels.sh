#!/bin/bash
# Build platform wheels and an sdist from a previously built qemu-img.com.
#
# The universal APE binary (src/cosmo_qemu_img/data/qemu-img.com) is shipped as
# is in the Windows and macOS wheels. Linux wheels instead ship a native ELF
# produced by assimilate, plus the pledge sandbox helper.
#
# Requirements:
#   - src/cosmo_qemu_img/data/qemu-img.com (see build_qemu_img_com.sh)
#   - python3 with the `build` and `wheel` packages
#   - assimilate (from cosmocc or cosmos) in PATH, or ASSIMILATE set
#   - PLEDGE set to the pledge binary to include it in Linux wheels (optional)
#
# Usage:
#   ./scripts/build_wheels.sh
#
# Output: dist/wheels/*.whl and dist/*.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${PROJECT_ROOT}/src/cosmo_qemu_img/data"
APE="${DATA_DIR}/qemu-img.com"
ASSIMILATE="${ASSIMILATE:-$(command -v assimilate || true)}"
PLEDGE="${PLEDGE:-}"

[ -f "${APE}" ] || { echo "Error: ${APE} not found" >&2; exit 1; }
[ -n "${ASSIMILATE}" ] || { echo "Error: assimilate not found (set ASSIMILATE)" >&2; exit 1; }

cd "${PROJECT_ROOT}"
VERSION=$(python3 -c "import sys; sys.path.insert(0, 'src'); from cosmo_qemu_img._version import __version__; print(__version__)")
echo "Building cosmo-qemu-img ${VERSION}"

rm -rf dist
mkdir -p dist/wheels

# Build a wheel from the current contents of the data directory and give it the
# requested platform tag ("wheel tags" rewrites the metadata, not just the name).
build_wheel() {
    local platform_tag=$1
    rm -rf build/lib build/bdist.* dist/tmp
    python3 -m build --wheel --outdir dist/tmp >/dev/null
    python3 -m wheel tags --platform-tag "${platform_tag}" --remove dist/tmp/*.whl >/dev/null
    mv dist/tmp/*.whl dist/wheels/
    rm -rf dist/tmp build/lib build/bdist.*
    echo "  built wheel for ${platform_tag}"
}

# Source distribution: contains the APE binary, licenses, patches and scripts
python3 -m build --sdist --outdir dist >/dev/null
echo "  built sdist"

# Windows and macOS wheels carry the APE binary only
for platform_tag in win_amd64 macosx_10_9_x86_64 macosx_11_0_arm64; do
    build_wheel "${platform_tag}"
done

# Linux wheels carry a native ELF, not the APE binary
STASH="$(mktemp)"
mv "${APE}" "${STASH}"
trap 'mv "${STASH}" "${APE}" 2>/dev/null || true; rm -f "${DATA_DIR}/qemu-img.elf" "${DATA_DIR}/pledge"' EXIT

if [ -n "${PLEDGE}" ]; then
    cp "${PLEDGE}" "${DATA_DIR}/pledge"
    chmod +x "${DATA_DIR}/pledge"
else
    echo "  warning: PLEDGE not set, Linux wheels will not include pledge"
fi

for entry in "x86_64:-x:manylinux_2_17_x86_64" "aarch64:-a:manylinux_2_17_aarch64"; do
    IFS=: read -r arch flag platform_tag <<<"${entry}"
    "${ASSIMILATE}" -e "${flag}" -o "${DATA_DIR}/qemu-img.elf" "${STASH}" >/dev/null
    chmod +x "${DATA_DIR}/qemu-img.elf"
    build_wheel "${platform_tag}"
done

ls -lh dist dist/wheels
