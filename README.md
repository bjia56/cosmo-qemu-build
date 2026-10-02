# cosmo-qemu-build

Build scripts and patches for [QEMU](https://www.qemu.org/) as
[Cosmopolitan libc](https://github.com/jart/cosmopolitan) executables: one file per program that
runs on Linux, macOS and Windows, on x86_64 and aarch64.

| Program | Notes |
| --- | --- |
| `qemu-img.com` | Disk image tool. |
| `qemu-system-x86_64.com` | x86_64 system emulator, firmware (SeaBIOS, edk2, ...) embedded. |
| `qemu-system-aarch64.com` | aarch64 system emulator, edk2 firmware embedded. |

## Acceleration

The system emulators choose an accelerator at run time, and TCG (software emulation) works everywhere:

| Accelerator | Where | Notes |
| --- | --- | --- |
| KVM | Linux, guest architecture = host architecture | Needs a usable `/dev/kvm`. |
| WHPX | Windows x86_64, x86_64 guests | Needs the "Windows Hypervisor Platform" feature. |
| HVF | macOS on Apple Silicon, aarch64 guests | See below. |

Use `-machine accel=kvm:tcg` (or `whpx:tcg`, `hvf:tcg`) to try an accelerator and fall back to TCG.

CI builds the executables on Linux and tests them there (x86_64 natively, aarch64 under qemu-user).
KVM, WHPX and HVF and the macOS and Windows startup paths need real hardware and are not exercised by CI.

**HVF and the loader.** Hypervisor.framework only works for a process signed with the
`com.apple.security.hypervisor` entitlement, and on Apple Silicon that process is the small loader the
executable compiles on its first run (this needs the Xcode command line tools, as for any Cosmopolitan
program). The executables use their own loader, `.q.ape-01` in `${TMPDIR:-$HOME}`, which signs itself with the
entitlement on first use, so HVF works without any setup. See [`patches/README.md`](patches/README.md).

Not included: network block drivers (curl, ssh, nfs, rbd, gluster), SASL, libgcrypt, Linux-specific I/O (io_uring, linux-aio),
GTK, OpenGL and vhost. The displays are the built-in VNC server and `-display sdl`, below.

## Display: VNC

`-vnc 127.0.0.1:0` serves the guest's display on port 5900, with no graphics library involved: QEMU's VNC server
needs only pixman, zlib and libjpeg-turbo (all built from source here), and ZRLE, Tight (with PNG and, through libjpeg-turbo, lossy JPEG), Hextile and zlib encodings work. `password=on` (set it with
`set_password vnc <pw>` in the monitor) and `websocket=<addr>:<port>` (for noVNC) are available.
TLS works through gnutls: create `-object tls-creds-x509,id=tls0,endpoint=server,dir=<certs>` and add `tls-creds=tls0` to
`-vnc` (VeNCrypt, which most clients speak; `verify-peer=on` asks for client certificates). SASL is not built. Without
`tls-creds`, bind VNC to localhost or tunnel it, since the built-in password authentication is weak.
The same credentials can be used wherever QEMU takes `tls-creds` (chardev sockets, NBD, migration); of these only the chardev case is exercised by CI.

## Display: SDL

`-display sdl` opens a native window using SDL2, which is loaded at run time (nothing is linked). On Windows (x64) and
macOS the executable embeds the official SDL2 release library, so nothing needs installing: it is extracted on first use
to your user cache directory (`%LOCALAPPDATA%\qemu-cosmo\Cache\sdl2`, `~/Library/Caches/qemu-cosmo/sdl2`) and loaded from
there, and a changed or tampered copy is replaced. On Linux there is no official binary, so install your distribution's
SDL2 (`libsdl2-2.0-0`). The host's own SDL2 is the fallback elsewhere. Without any, QEMU says so and exits; `-display vnc` needs nothing. Only the 2D renderer is supported (no
`gl=on`, no SDL audio), and SDL is never chosen by default.

Tested on Linux only, under Xvfb (`scripts/smoke_test_sdl.sh`), with the cache logic covered by
`scripts/test_sdl2_cache.sh`. The embedded Windows and macOS libraries and the paths that load them have never been run
(including SDL's main-thread requirement on macOS).

## Sharing a host directory (virtfs / 9p)

The system emulators include QEMU's 9p file sharing (`-virtfs` / `-fsdev local` with `virtio-9p-pci`), so a guest
can mount a host directory with `mount -t 9p -o trans=virtio,version=9p2000.L <mount_tag> /mnt`:

```bash
./qemu-system-x86_64.com ... -virtfs local,path=/some/dir,mount_tag=host,security_model=mapped-file,id=host
```

| `security_model` | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- |
| `none` | yes | expected | expected | Files are created with the host user's ownership and permissions. |
| `mapped-file` | yes | expected | expected | Guest ownership and mode are kept in `.virtfs_metadata` files next to the data. |
| `mapped-xattr` | yes | no | no | Needs extended attributes, which are only reachable on Linux; elsewhere QEMU refuses it at startup. |
| `passthrough` | yes | no | no | Needs `chown` to arbitrary users, so it is only meant for Linux hosts (as root). |

Device nodes and symlink containment are limited off Linux (see [`patches/README.md`](patches/README.md), patch `15`).
CI starts the 9p device on Linux only, and a guest mounting a share has only been tried on Linux; "expected" means
the macOS and Windows code paths are written for it but have not been run (they need real hardware).

## Getting the binaries

The [Build workflow](.github/workflows/build.yml) builds everything and uploads one artifact per
program. There are no releases yet. Downloaded artifacts lose the executable bit: run
`chmod +x qemu-*.com`, or start them with `sh ./qemu-img.com`. The license texts are inside every
executable (Cosmopolitan serves the zip archive appended to it): `unzip -p qemu-img.com COPYING` and
`unzip -p qemu-img.com THIRD_PARTY_NOTICES.txt`.

## Building from source

The build runs on Linux (bash 4 or later). It requires [cosmocc](https://cosmo.zip/pub/cosmocc/) with
`assimilate`, `apelink` and `fixupobj` (tested with 4.0.2; the macOS loader patch is written for that
release), plus `git`, `curl`, `tar`, `sed`, `make`, `patch`, `zip`, `bzip2`, `ninja`, `pkg-config`,
`python3`, `cmake`, `7z`, `unzip`, `sha256sum`, `meson` (>= 1.5, for example from `pipx install meson`), `qemu-aarch64-static`
(to run aarch64 configure-time probes) and the Linux kernel headers for each host architecture
(`linux-libc-dev` and `linux-libc-dev-arm64-cross` on Debian/Ubuntu):

```bash
./scripts/build.sh                       # everything, into ./out
./scripts/smoke_test_aarch64.sh out      # the aarch64 halves, under qemu-user
```

`scripts/build.sh` runs the smoke tests for the x86_64 halves itself. It compiles zlib, libpng, libjpeg-turbo, pcre2, nettle, gnutls, bzip2, zstd, libffi,
glib and pixman for each architecture into a static sysroot, then builds QEMU from a tagged release and
links both architectures into one file per program with `apelink`. The Cosmopolitan-specific changes to
glib and QEMU are in [`patches/`](patches), and [`compat/`](compat) holds the header shims and the macOS
loader patch they need. Sources are fetched by tag and checked against pinned commits, and downloads are
checked against pinned SHA-256 sums.

Environment variables (the top of [`scripts/build.sh`](scripts/build.sh) documents them): `ARCHES` and
`SYSTEM_TARGETS` (defaults: `x86_64 aarch64`; an empty `SYSTEM_TARGETS` builds only `qemu-img`),
`BUILD_DIR`, `OUT_DIR`, `JOBS`, `QEMU_VERSION` (only versions that have a directory under
[`patches/qemu/`](patches/qemu) are supported; currently `v9.2.0`), `EXE_WRAPPER_<arch>`,
`KERNEL_HEADERS_<arch>`, `QEMU_REPO`, `GLIB_REPO` and `WHP_HEADERS_URL`.

## License

The build scripts and the files in `compat/` (our own header shims) are MIT; see [LICENSE](LICENSE). The
patches are changes to QEMU and glib and carry the license of the file they modify (mostly GPL-2.0-or-later
for QEMU and LGPL-2.1-or-later for glib). `compat/ape/ape-m1-hypervisor.patch` modifies Cosmopolitan's
`ape-m1.c` (ISC). Microsoft's MIT-licensed Windows Hypervisor Platform headers are fetched at build time
and are not stored in this repository.

The executables are built from [QEMU](https://www.qemu.org/), which is licensed under the GPL-2.0, see
[COPYING](https://gitlab.com/qemu-project/qemu/-/blob/master/COPYING). They statically link
[Cosmopolitan Libc](https://github.com/jart/cosmopolitan) (ISC, with the notices of the third-party code it
bundles embedded in the executables), glib and proxy-libintl (LGPL-2.1+), libpng (libpng license), libjpeg-turbo (IJG, BSD-3-Clause and zlib), gnutls (LGPL-2.1+, with its bundled libtasn1 and libunistring), pcre2 (BSD), nettle (LGPL-3.0+ or GPL-2.0+, used under the GPL), bzip2 (bzip2 license), zstd (BSD-3-Clause), libffi (MIT), zlib
(zlib), pixman (MIT) and libslirp (BSD-3-Clause). `COPYING` and `THIRD_PARTY_NOTICES.txt`, with all of their license texts, are
embedded in each executable.

The corresponding source for an executable is the QEMU tag it was built from (`QEMU_VERSION` in
[`scripts/build.sh`](scripts/build.sh)) together with the patches and scripts in this repository at the
same commit.
