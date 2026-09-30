#!/bin/bash
# Helpers: logging, downloads, git clones, patches.
# Sourced by scripts/build.sh; relies on the variables it defines.

die() { echo "Error: $*" >&2; exit 1; }

# run_logged <name> <command...>: run quietly, dump the log tail on failure
run_logged() {
    local name=$1; shift
    local log="${LOG_DIR}/${name}.log"
    echo "  ${name}..."
    if ! "$@" >"${log}" 2>&1; then
        echo "Error: step '${name}' failed. Last lines of ${log}:" >&2
        tail -n 40 "${log}" >&2
        exit 1
    fi
}

# run_logged <name> <command...>: run quietly, dump the log tail on failure
run_logged() {
    local name=$1; shift
    local log="${LOG_DIR}/${name}.log"
    echo "  ${name}..."
    if ! "$@" >"${log}" 2>&1; then
        echo "Error: step '${name}' failed. Last lines of ${log}:" >&2
        tail -n 40 "${log}" >&2
        exit 1
    fi
}

# download <sha256> <output name> <url>...: try each URL until one matches
download() {
    local sha=$1 name=$2; shift 2
    local out="${DL_DIR}/${name}" url
    if [ -f "$out" ] && echo "${sha}  ${out}" | sha256sum -c --status; then
        return 0
    fi
    for url in "$@"; do
        echo "  downloading ${name} from ${url}"
        if curl --retry 5 --retry-delay 5 -sSfL -o "$out" "$url" \
            && echo "${sha}  ${out}" | sha256sum -c --status; then
            return 0
        fi
        echo "  (failed or checksum mismatch, trying next mirror)"
    done
    die "could not download ${name} with a matching checksum"
}

# clone_tag <repo> <tag> <dest>
clone_tag() {
    echo "  cloning $(basename "$1" .git) $2"
    GIT_LFS_SKIP_SMUDGE=1 git -c advice.detachedHead=false clone -q --depth 1 --branch "$2" "$1" "$3"
    [ -d "$3/.git" ] || die "clone of $1 failed"
}

# apply_patches <component> <version> <source dir>
apply_patches() {
    local dir="${PROJECT_ROOT}/patches/$1/$2"
    [ -d "$dir" ] || return 0
    local p
    for p in "$dir"/*.patch; do
        [ -f "$p" ] || continue
        echo "  applying $1/$(basename "$p")"
        patch -s -p1 -d "$3" < "$p"
    done
}
