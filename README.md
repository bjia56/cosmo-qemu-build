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

CI builds on Linux, then runs the smoke tests on native runners: Linux x86_64 and aarch64, macOS arm64 and
Windows x86_64, and all of them must pass for a release. A WHPX guest boots on the Windows runner. KVM and
HVF need hardware the runners do not provide and are untested.

HVF needs the `com.apple.security.hypervisor` entitlement on the loader that Cosmopolitan compiles on first
run (needs the Xcode command line tools). The executables use their own loader, `.q.ape-01` in
`${TMPDIR:-$HOME}`, which signs itself on first use; see [`patches/README.md`](patches/README.md).

Not included: network block drivers (curl, ssh, nfs, rbd, gluster), SASL, libgcrypt, io_uring, linux-aio,
GTK, OpenGL and vhost.

## Display: VNC

`-vnc 127.0.0.1:0` serves the display on port 5900 and needs no graphics library. `password=on` and
`websocket=<addr>:<port>` (noVNC) work. TLS works through gnutls: add
`-object tls-creds-x509,id=tls0,endpoint=server,dir=<certs>` and `tls-creds=tls0` to `-vnc` (VeNCrypt).
Without `tls-creds`, bind to localhost or tunnel, since VNC password authentication is weak. Only the
chardev socket case of `tls-creds` is exercised by CI.

## Display: SDL

`-display sdl` opens a native window using SDL2, loaded at run time (nothing is linked). On Windows (x64) and
macOS the executable embeds the official SDL2 release library and extracts it on first use to the user cache
directory (`%LOCALAPPDATA%\qemu-cosmo\Cache\sdl2`, `~/Library/Caches/qemu-cosmo/sdl2`). On Linux install
your distribution's SDL2 (`libsdl2-2.0-0`), which is also the fallback elsewhere. Only the 2D renderer is
supported (no `gl=on`, no SDL audio), and SDL is never the default. On Windows the software renderer is used (the GPU drivers' own
exceptions are fatal under Cosmopolitan); set `SDL_RENDER_DRIVER` to override it.

CI runs `scripts/smoke_test_sdl.sh` on every runner (Linux under Xvfb): the guest runs, nothing crashes and, except on macOS, a window titled QEMU opens.

## Sharing a host directory (virtfs / 9p)

`-virtfs` / `-fsdev local` with `virtio-9p-pci`; the guest mounts it with
`mount -t 9p -o trans=virtio,version=9p2000.L <mount_tag> /mnt`:

```bash
./qemu-system-x86_64.com ... -virtfs local,path=/some/dir,mount_tag=host,security_model=mapped-file,id=host
```

| `security_model` | Linux | macOS | Windows | Notes |
| --- | --- | --- | --- | --- |
| `none` | yes | expected | expected | Host user's ownership and permissions. |
| `mapped-file` | yes | expected | expected | Guest ownership and mode kept in `.virtfs_metadata` files. |
| `mapped-xattr` | yes | no | no | Needs xattrs, reachable only on Linux; refused at startup elsewhere. |
| `passthrough` | yes | no | no | Needs `chown` to arbitrary users (Linux, as root). |

Device nodes and symlink containment are limited off Linux (patch `15`). Only Linux has been run: "expected"
means the macOS and Windows code is written for it but untested.

## Memory ballooning

`-device virtio-balloon-pci` (with `free-page-reporting=on` and `deflate-on-oom=on`) returns guest RAM to the
host, so a guest can be given most of the host's memory and still follow its pressure (patch `22`):

| Host | Guest pages given back | Notes |
| --- | --- | --- |
| Linux | freed (`MADV_DONTNEED`) | |
| macOS | expected (`MADV_FREE`) | Apple Silicon hosts use 16 KiB pages: the guest must give back whole, aligned 16 KiB ranges. |
| Windows | expected (`DiscardVirtualMemory`) | Windows 8.1 or later. Guest RAM must be private anonymous memory (the default). |

CI inflates a legacy virtio-balloon from a boot sector on every runner and fails if QEMU reports a page it could not
discard. Only Linux has been run: "expected" means the macOS and Windows code is written for it but untested. The test does
not measure the host's memory use, and the balloon is untested with WHPX and HVF guests.
virtio-mem is not built (it needs Linux). `memory-backend-*` objects with `share=on` or a file keep the old calls.

## Sandboxing

`-sandbox on` is enforced differently per host:

| Host | Mechanism | Supported switches |
| --- | --- | --- |
| Linux | seccomp (libseccomp 2.6.0) | all: `obsolete`, `elevateprivileges`, `spawn`, `resourcecontrol` |
| macOS | Seatbelt profile (`sandbox_init`) | `spawn=deny` only |
| Windows | child-process mitigation policy (`SetProcessMitigationPolicy`) | `spawn=deny` only |

`spawn=deny` stops the monitor from starting processes (`migrate "exec:..."` fails with "Failed to fork").
On macOS and Windows every other switch is refused and `-sandbox on` alone is an error, so the flag never
silently does nothing; neither restricts files or the network. FreeBSD, OpenBSD and NetBSD have no sandbox.

CI runs the sandbox tests and the system emulator suite under `-sandbox` on all four runners. KVM is untested
under the sandbox.

## Getting the binaries

The [Build workflow](.github/workflows/build.yml) uploads one artifact per program. Downloads lose the
executable bit: `chmod +x qemu-*.com`, or run `sh ./qemu-img.com`. License texts are embedded:
`unzip -p qemu-img.com COPYING` and `unzip -p qemu-img.com THIRD_PARTY_NOTICES.txt`.

## Building from source

Linux with bash 4+. Requires [cosmocc](https://cosmo.zip/pub/cosmocc/) with
`assimilate`, `apelink` and `fixupobj` (4.0.2; the macOS loader patch is written for that release), plus `git`, `curl`, `tar`, `sed`, `make`, `patch`, `zip`, `bzip2`, `ninja`, `pkg-config`,
`python3`, `cmake`, `gperf`, `objdump`, `7z`, `unzip`, `sha256sum`, `meson` (>= 1.5, for example from `pipx install meson`), `qemu-aarch64-static`
(to run aarch64 configure-time probes) and the Linux kernel headers for each host architecture
(`linux-libc-dev` and `linux-libc-dev-arm64-cross` on Debian/Ubuntu):

```bash
./scripts/build.sh                       # everything, into ./out
./scripts/smoke_test_all.sh out          # every smoke test, natively (Linux, macOS, Windows under Git Bash)
```

`build.sh` does not run the smoke tests. It builds the dependencies per architecture into a static
sysroot, builds QEMU from a tagged release, and joins both architectures with `apelink`. Cosmopolitan-specific
changes are in [`patches/`](patches); [`compat/`](compat) holds header shims and the macOS loader patch.
Sources are checked against pinned commits and downloads against pinned SHA-256 sums.

Environment variables are documented at the top of [`scripts/build.sh`](scripts/build.sh). Only
`QEMU_VERSION`s with a directory under [`patches/qemu/`](patches/qemu) work (currently `v9.2.0`).

## License

The build scripts and the files in `compat/` (our own header shims) are MIT; see [LICENSE](LICENSE). Patches
carry the license of the file they modify (mostly GPL-2.0-or-later for QEMU, LGPL-2.1-or-later for glib). `compat/ape/ape-m1-hypervisor.patch` modifies Cosmopolitan's
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
