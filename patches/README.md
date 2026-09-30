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
| `09-cosmo-enable-whpx` | WHPX for x86_64 guests on the x86_64 host slice. `LoadLibrary`/`GetProcAddress` become `cosmo_dlopen`/`cosmo_dlsym` + `cosmo_dltramp` (entry points are called through System V trampolines, emulator callbacks stay Microsoft x64 `CALLBACK`), the load is gated on `IsWindows()`, `HRESULT` constants and diagnostics are fixed for LP64, and the meson gate accepts the `cosmopolitan` host OS. The WHP headers come from mingw-w64 at build time; `compat/whp/` supplies the few base Windows types they need. |
| `10-cosmo-windows-early-startup` | Windows' `getrlimit(RLIMIT_NOFILE)` fails with `EINVAL` under Cosmopolitan, which made `os_setup_limits()` warn before the monitor's globals exist and hit an uninitialized mutex. Skip that warning, and make `monitor_cur()` safe before `monitor_init_globals()` so any early message is printed instead of crashing. |
| `11-cosmo-windows-ram-mmap` | On Windows, Cosmopolitan can only unmap or `MAP_FIXED`-replace whole allocations, but QEMU's RAM allocator reserves a `PROT_NONE` region, re-maps a piece of it and trims the rest (`ENOTSUP`, seen as "cannot set up guest memory"). When running on Windows, map RAM directly and unmap exactly what was mapped. Other operating systems keep the original code. |
| `12-cosmo-crash-reports` | Call Cosmopolitan's `ShowCrashReports()` (declared by `-mcosmo`) at the start of `main()`, so a crash, abort or `SIGFPE` prints registers, a backtrace and a `cosmoaddr2line` command instead of a bare "terminating on uncaught signal". |
| `13-cosmo-block-sizes-sanity` | A block-size probe that reports success with zero sizes made `blkconf_blocksizes()` divide by zero (SIGFPE) on Windows. Ignore such a probe with a warning, and fail with an error that prints the state if the sizes are still zero. |
| `14-cosmo-file-posix-unsupported-flags` | Cosmopolitan defines an `O_*` flag a system lacks as all ones, not zero (`O_ASYNC` is `0xffffffff` on Windows), so the `(open_flags & O_ASYNC) == 0` assertion in `raw_reconfigure_getfd()` always failed there, aborting at shutdown. Skip it on Cosmopolitan. |
| `15-cosmo-whpx-ignore-invalid-msi` | With the in-kernel APIC, the guest's startup produces one all-zero MSI (fixed interrupt, vector 0). `WHvRequestInterrupt` fast-fails (`0xC0000409`) on it instead of returning an error, so `whpx_send_msi()` drops fixed interrupts below vector 16. Without this the default (in-kernel irqchip) WHPX configuration crashes on Windows. |
| `16-cosmo-mcosmo-name-collisions` | The build compiles QEMU with `-mcosmo` (`_COSMO_SOURCE`). Cosmopolitan's headers then `#define` `startswith` and `rdrand`, colliding with QEMU's static `startswith()` in `gdbstub.c` (renamed) and with the `rdrand` TCG helper (`#undef rdrand` in `translate.c` and `int_helper.c`, so the helper keeps one name in both). |
| `17-cosmo-aarch64-cache-macos` | On an aarch64 host, QEMU reads `CTR_EL0` to size and flush the caches, which raises `SIGILL` on macOS (a crash before `main()`). Outside Linux, skip that read (line sizes fall back to `sysconf`/64) and flush through Cosmopolitan's `__clear_cache()`, which calls the macOS `sys_icache_invalidate`. |
| `18-cosmo-macos-jit` | TCG on Apple Silicon needs the code buffer mapped with `MAP_JIT` and the per-thread write/execute toggle (`pthread_jit_write_protect_np`), both of which QEMU only does for `CONFIG_DARWIN`. Under Cosmopolitan, add `MAP_JIT` (zero on other systems) to the buffer and implement `qemu_thread_jit_write/execute` with Cosmopolitan's `__jit_begin()`/`__jit_end()` (no-ops elsewhere). Without it the buffer's `mprotect` fails with `EACCES`. |
| `19-cosmo-enable-hvf` | HVF for aarch64 guests on the aarch64 host slice. `Hypervisor.framework` is loaded with `cosmo_dlopen` when the accelerator initializes (`accel/hvf/hvf-cosmo.c`), and every `hv_*` call (plus `mach_absolute_time` and `os_release` from libSystem) goes through a function table, so nothing links against the framework. The header QEMU includes is `compat/hvf/Hypervisor/Hypervisor.h`, a minimal interface written for this build; the meson gate accepts the `cosmopolitan` host OS on aarch64. Initialization fails cleanly off Apple Silicon, and an `HV_DENIED` result explains the missing `com.apple.security.hypervisor` entitlement. |

Patches `04`-`19` are only needed for the system emulators; they are harmless
for the `qemu-img` build.

### Building system emulators

System emulators additionally need the base Linux kernel headers (`linux/types.h`,
`linux/ioctl.h`, ... and `asm-generic/*`, plus the per-architecture `asm/*`) for the target
host architecture in the sysroot, because QEMU's vendored `linux/kvm.h` includes them
(`linux-libc-dev`, and `linux-libc-dev-arm64-cross` for aarch64). Do not copy the kernel's
own `kvm.h` there; QEMU's vendored copy must win. Any `ninja` run after a `meson.build`
change must keep `PKG_CONFIG_PATH`/`PKG_CONFIG_LIBDIR` pointing at the sysroot, or the
regenerated build picks up host libraries.
