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

**HVF and the loader.** Hypervisor.framework only works for a process signed with the
`com.apple.security.hypervisor` entitlement, and on Apple Silicon that process is the small loader the
executable compiles on its first run (this needs the Xcode command line tools, as for any Cosmopolitan
program). The executables use their own loader, `.q.ape-01` in `${TMPDIR:-$HOME}`, which signs itself with the
entitlement on first use, so HVF works without any setup. See [`patches/README.md`](patches/README.md).

Not included: network block drivers (curl, ssh, nfs, rbd, gluster), encryption backed by
gnutls/nettle/gcrypt, zstd and bzip2 compression, Linux-specific I/O (io_uring, linux-aio), 9p/virtfs,
graphics front ends (SDL, GTK, ...), vhost and user-mode networking (slirp).

## Getting the binaries

The [Build workflow](.github/workflows/build.yml) builds everything and uploads one artifact per
program. There are no releases yet. Downloaded artifacts lose the executable bit: run
`chmod +x qemu-*.com`, or start them with `sh ./qemu-img.com`. The license texts are inside every
executable (Cosmopolitan serves the zip archive appended to it): `unzip -p qemu-img.com COPYING` and
`unzip -p qemu-img.com THIRD_PARTY_NOTICES.txt`.

## Building from source

Requires [cosmocc](https://cosmo.zip/pub/cosmocc/) (with `assimilate`, `apelink` and `fixupobj`), plus
`git`, `curl`, `make`, `patch`, `zip`, `bzip2`, `ninja`, `pkg-config`, `python3`, `meson` (>= 1.5),
`qemu-aarch64-static` (to run aarch64 configure-time probes), the Linux kernel headers for each host
architecture (`linux-libc-dev` and `linux-libc-dev-arm64-cross` on Debian/Ubuntu):

```bash
./scripts/build.sh                       # everything, into ./out
./scripts/smoke_test_aarch64.sh out      # the aarch64 halves, under qemu-user
```

`scripts/build.sh` runs the smoke tests for the x86_64 halves itself. It compiles zlib, pcre2, libffi,
glib and pixman for each architecture into a static sysroot, then builds QEMU from a tagged release (set
`QEMU_VERSION`, default `v9.2.0`) and links both architectures into one file per program with `apelink`.
The Cosmopolitan-specific changes to glib and QEMU are in [`patches/`](patches), and
[`compat/`](compat) holds the header shims and the macOS loader patch they need.

Useful environment variables: `ARCHES` and `SYSTEM_TARGETS` (defaults: `x86_64 aarch64`; an empty
`SYSTEM_TARGETS` builds only `qemu-img`), `BUILD_DIR`, `OUT_DIR`, `JOBS`. The top of
[`scripts/build.sh`](scripts/build.sh) lists them all.

## License

The build scripts in this repository are MIT - See [LICENSE](LICENSE). The patches are changes to QEMU
and glib and carry their licenses (GPL-2.0-or-later and LGPL-2.1-or-later).

The binaries are built from [QEMU](https://www.qemu.org/), which is licensed under the GPL-2.0, see
[COPYING](https://gitlab.com/qemu-project/qemu/-/blob/master/COPYING); it is embedded in each binary.
They statically link glib (LGPL-2.1+), pcre2 (BSD), libffi (MIT), zlib (zlib) and pixman (MIT); their
license texts are in the embedded `THIRD_PARTY_NOTICES.txt`.

The corresponding source for a binary is the QEMU tag it was built from (`QEMU_VERSION` in
[`scripts/build.sh`](scripts/build.sh)) together with the patches and scripts in this repository at the
same commit.
