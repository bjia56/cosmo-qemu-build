#!/bin/sh
# SPDX-License-Identifier: MIT
# Tests how the emulator extracts the SDL2 library it embeds (Windows and macOS
# builds) into the user's cache directory, on Linux. The embedded library is
# replaced by a copy of the host's libSDL2 through QEMU_COSMO_SDL2_BUNDLE, and the
# cache location comes from XDG_CACHE_HOME (the same code picks %LOCALAPPDATA%
# and ~/Library/Caches elsewhere). Needs libSDL2 on the host; skips without it.
#
# Usage: ./scripts/test_sdl2_cache.sh "sh /path/to/qemu-system-x86_64.com"

set -eu

QEMU="${1:-${QEMU_SYSTEM:-}}"
if [ -z "$QEMU" ]; then
    echo "usage: $0 <qemu-system command>" >&2
    exit 2
fi
LIB=""
for cand in /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 /usr/lib/aarch64-linux-gnu/libSDL2-2.0.so.0 \
            /usr/lib64/libSDL2-2.0.so.0 /usr/lib/libSDL2-2.0.so.0; do
    [ -f "$cand" ] && LIB=$cand && break
done
[ -n "$LIB" ] || { echo "skip - no host libSDL2"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -L "$LIB" "$TMP/bundle.so"
export XDG_CACHE_HOME="$TMP/cache" QEMU_COSMO_SDL2_BUNDLE="$TMP/bundle.so"
CACHE="$XDG_CACHE_HOME/qemu-cosmo/sdl2"

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; exit 1; }
# the monitor's "quit" ends the emulator whether or not SDL could open a display
run() { echo quit | $QEMU -display sdl -S -m 32 -net none -monitor stdio -serial none > "$TMP/out.txt" 2>&1 || true; }
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
sum() { sha256sum "$1" | cut -d' ' -f1; }

want=$(sum "$TMP/bundle.so")

run
f=$(ls "$CACHE"/SDL2-*.so 2>/dev/null | head -n 1)
[ -n "$f" ] || fail "library extracted into \$XDG_CACHE_HOME/qemu-cosmo/sdl2"
[ "$(sum "$f")" = "$want" ] || fail "extracted library is identical to the embedded one"
case "$(basename "$f")" in SDL2-"$(echo "$want" | cut -c1-16)".so) ;; *) fail "file name carries the SHA-256" ;; esac
[ "$(mode "$CACHE")" = 700 ] && [ "$(mode "$f")" = 600 ] || fail "private modes (dir 700, file 600)"
grep -a -q "cannot load the SDL2 library" "$TMP/out.txt" && fail "the extracted library loads"
pass "extracted to the cache directory, named by hash, private"

ino=$(ls -i "$f" | cut -d' ' -f1)
run
[ "$(ls -i "$f" | cut -d' ' -f1)" = "$ino" ] || fail "an intact library is reused, not rewritten"
pass "an intact cached library is reused"

printf 'tampered' >> "$f"
run
[ "$(sum "$f")" = "$want" ] || fail "a modified library is replaced"
pass "a modified cached library is replaced"

rm -f "$f"; ln -s /nonexistent "$f"
run
[ -f "$f" ] && [ ! -L "$f" ] && [ "$(sum "$f")" = "$want" ] || fail "a symlink in place of the library is replaced"
pass "a symlink in place of the library is replaced"

chmod 777 "$CACHE"
run
[ "$(mode "$CACHE")" = 700 ] || fail "an open cache directory is closed to other users"
pass "a world-writable cache directory is made private"

rm -rf "$XDG_CACHE_HOME"; mkdir -p "$XDG_CACHE_HOME/qemu-cosmo" "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$CACHE"
run
[ -z "$(ls "$TMP/elsewhere")" ] || fail "nothing is written through a symlinked cache directory"
pass "a symlinked cache directory is not used"

echo "All SDL2 cache tests passed"
