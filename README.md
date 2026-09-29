# cosmo-qemu

[QEMU](https://www.qemu.org/) built with [Cosmopolitan libc](https://github.com/jart/cosmopolitan), so a
single executable runs on Linux, macOS and Windows.

This repository currently builds `qemu-img` and distributes it as the `cosmo-qemu-img` Python package.
Work on the system emulators (TCG, plus KVM on Linux) is in progress; the Cosmopolitan-specific changes
for it already live in [`patches/`](patches).

## cosmo-qemu-img

Cross-platform `qemu-img` command built with Cosmopolitan libc, distributed as a Python package.

## Installation

```bash
pip install cosmo-qemu-img
```

## Usage

### Command Line

```bash
cosmo-qemu-img create -f qcow2 disk.qcow2 10G
cosmo-qemu-img info disk.qcow2
cosmo-qemu-img convert -f raw -O qcow2 disk.raw disk.qcow2
cosmo-qemu-img --version
```

### Python API

```python
import cosmo_qemu_img

cosmo_qemu_img.run('create', '-f', 'qcow2', 'disk.qcow2', '10G', check=True)

result = cosmo_qemu_img.run('info', '--output=json', 'disk.qcow2')
print(result.stdout.decode())
```

An async variant, `cosmo_qemu_img.run_async()`, takes the same arguments.

## Features

- Single universal binary runs on Windows, macOS, and Linux
- No external dependencies
- Python 3.8+ compatible
- Supports the qemu-img image formats and subcommands that do not need optional
  libraries: `create`, `info`, `convert`, `check`, `compare`, `snapshot`, `commit`,
  `resize`, `rebase`, `measure`, `map`, `bitmap`, and more

Not included in this build: network block drivers (curl, ssh, nfs, rbd, gluster),
encryption backed by gnutls/nettle/gcrypt, zstd and bzip2 compression, and Linux-specific
I/O (io_uring, linux-aio). qcow2 zlib compression is supported.

## Platforms

- Windows x64
- macOS x86_64 / ARM64
- Linux x86_64 / ARM64

Linux wheels ship a native ELF for the architecture. Optional sandboxing with
[pledge](https://justine.lol/pledge/) is available on Linux with
`cosmo_qemu_img.run(..., pledge=True)`; it is experimental and off by default.

## Building from Source

Requires [cosmocc](https://cosmo.zip/pub/cosmocc/), plus `git`, `curl`, `make`, `patch`,
`zip`, `bzip2`, `ninja`, `pkg-config`, `meson`, `qemu-user-static` (to run aarch64 configure-time
probes) and the Linux kernel headers for each host architecture (`linux-libc-dev` and
`linux-libc-dev-arm64-cross` on Debian/Ubuntu):

```bash
./scripts/build.sh
./scripts/smoke_test.sh "sh src/cosmo_qemu_img/data/qemu-img.com"
./scripts/smoke_test_system.sh "sh out/qemu-system-x86_64.com" x86_64
pip install -e .
```

The build compiles zlib, pcre2, libffi, glib and pixman for each architecture into a static
sysroot, then builds `qemu-img` and the system emulators from a tagged QEMU release and links
both architectures with `apelink`. Cosmopolitan-specific changes to glib and QEMU are in
[`patches/`](patches). Platform wheels and an sdist are produced by `./scripts/build_wheels.sh`.

`qemu-img` goes to `src/cosmo_qemu_img/data/qemu-img.com`. The system emulators
(`qemu-system-x86_64` and `qemu-system-aarch64`) go to `out/qemu-system-<guest>.com`, each with
its firmware embedded, and are not part of the Python package yet. They compile in KVM (used
on Linux when the guest architecture matches the host and `/dev/kvm` is usable) and TCG;
pick between them at run time with `-machine accel=kvm:tcg`. Set `SYSTEM_TARGETS=` (empty)
to build only `qemu-img`, or `ARCHES=x86_64` to build for one host architecture.

## License

The Python packaging in this repository is MIT - See [LICENSE](LICENSE).

The bundled `qemu-img` binary is built from [QEMU](https://www.qemu.org/) and is licensed under
the GPL-2.0, see [COPYING](https://gitlab.com/qemu-project/qemu/-/blob/master/COPYING). It statically
links glib (LGPL-2.1+), pcre2 (BSD), libffi (MIT) and zlib (zlib); their license texts ship with the
package in `THIRD_PARTY_NOTICES.txt`.

The corresponding source for the binary is the QEMU tag named in
`src/cosmo_qemu_img/_version.py` together with the patches and build scripts in this repository, all of
which are also included in the source distribution.
