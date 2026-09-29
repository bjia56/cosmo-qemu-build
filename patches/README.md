# Patches

Cosmopolitan-specific changes applied on top of upstream sources by
`scripts/build.sh`. Patches are grouped by component and upstream
version, and applied in filename order.

## `glib/2.82.4`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-drop-nonblock-static-assert` | `O_NONBLOCK` is a runtime value under Cosmopolitan, so the compile-time assertion cannot hold. |
| `02-cosmo-runtime-sysdef-constants` | `POLL*` and `AF_*`/`MSG_*` are runtime values too; when the build-time probe cannot compute them, fall back to the Linux constants for `glibconfig.h`. |
| `03-cosmo-g_poll-translate-events` | Translate `G_IO_*` to and from the runtime `POLL*` values around `poll()` (they differ on Windows). |

## `qemu/v9.2.0`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-host-os` | Detect Cosmopolitan in `configure` and use a distinct `cosmopolitan` host OS, so QEMU takes its portable POSIX paths instead of Linux-only ones (raw futex, `linux/*.h`). |
| `02-cosmo-mmap-alloc` | `MAP_SYNC` and `MAP_SHARED_VALIDATE` handling, and `TMPFS_MAGIC`, without `linux/*.h`. |
| `03-cosmo-poll-translate-events` | Translate `G_IO_*` to and from the runtime `POLL*` values in `qemu_poll_ns()`. |
| `04-cosmo-migration-iov-max` | `IOV_MAX` is a runtime value; use the smallest value on any OS (16, Windows) for the migration `iovec` array. |
| `05-cosmo-net-colo-ipproto` | Define `IPPROTO_ESP` and `IPPROTO_AH`, which Cosmopolitan's headers lack. |
| `06-cosmo-eventfd-linux-syscall` | Add `include/qemu/cosmo-linux-syscall.h` (raw Linux system calls, guarded by `IsLinux()`) and use it for a real `eventfd2` in `EventNotifier`, falling back to a pipe on other operating systems. |
| `07-cosmo-enable-kvm` | Allow the KVM accelerator on the `cosmopolitan` host OS: meson gates, vendored `linux-headers` include path and `asm` symlink, `arch_prctl` via the raw-syscall helper, kernel-typed `VMSTATE_*` macros, and Xen emulation off by default. KVM is only usable at runtime on Linux; elsewhere `/dev/kvm` cannot be opened and QEMU falls back to the next accelerator. |

| `08-cosmo-aarch64-tcg-reserve-x28` | Cosmopolitan keeps its thread-local storage base in `x28` on aarch64, so the aarch64 TCG backend must not allocate it. Without this, generated code clobbers `x28` and the next helper call crashes on a thread-local access (seen as a segfault in `rcu_read_lock()` when booting an x86 guest on an aarch64 host). |

Patches `04`-`08` are only needed for the system emulators; they are harmless
for the `qemu-img` build.

### Building system emulators

System emulators additionally need the base Linux kernel headers (`linux/types.h`,
`linux/ioctl.h`, ... and `asm-generic/*`, plus the per-architecture `asm/*`) for the target
host architecture in the sysroot, because QEMU's vendored `linux/kvm.h` includes them
(`linux-libc-dev`, and `linux-libc-dev-arm64-cross` for aarch64). Do not copy the kernel's
own `kvm.h` there; QEMU's vendored copy must win. Any `ninja` run after a `meson.build`
change must keep `PKG_CONFIG_PATH`/`PKG_CONFIG_LIBDIR` pointing at the sysroot, or the
regenerated build picks up host libraries.
