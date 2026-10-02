# Patches

Cosmopolitan-specific changes applied by `scripts/build.sh` with `patch -p1`, per component and
upstream version, in filename order. One topic per patch, so a newer upstream means resolving
conflicts one topic at a time. Patches `03`-`07` and `15` are only needed for the system
emulators.

## `glib/2.82.4`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-portability` | `O_NONBLOCK`, `POLL*` and `AF_*`/`MSG_*` are run-time values: drop the compile-time `O_NONBLOCK` assertion, fall back to Linux constants for `glibconfig.h`, and translate `G_IO_*` to and from `POLL*` around `poll()` (they differ on Windows). |

## `libslirp/4.9.3`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-portability` | No `if_nametoindex()`: ignore the interface scope in `nameserver fe80::1%eth0`. |
| `02-cosmo-sscanf-scansets` | `cosmo_sscanf()` (as QEMU patch `10`) for `resolv.conf`, FTP and IRC parsing. |

## `qemu/v9.2.0`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-portability` | Detect Cosmopolitan in `configure` as a distinct `cosmopolitan` host OS, so QEMU takes portable POSIX paths instead of Linux-only ones. Plus missing definitions, `G_IO_*` translation in `qemu_poll_ns()`, and the smallest `IOV_MAX` of any OS (16, Windows). |
| `02-cosmo-mcosmo` | QEMU is built with `-mcosmo`: call `ShowCrashReports()` in `main()` and fix the two name collisions (`startswith()` in `gdbstub.c`, the `rdrand` TCG helper). |
| `03-cosmo-enable-kvm` | KVM on the `cosmopolitan` host OS: meson gates, vendored `linux-headers`, `arch_prctl` and `eventfd2` as raw Linux system calls (guarded by `IsLinux()`; a pipe elsewhere). `/dev/kvm` cannot be opened off Linux, so QEMU falls back to the next accelerator. |
| `04-cosmo-aarch64-host` | aarch64 TCG: `x28` holds Cosmopolitan's TLS base, so the backend must not allocate it (segfault in `rcu_read_lock()`). On macOS, reading `CTR_EL0` raises `SIGILL`, so skip it outside Linux; use `MAP_JIT` and `__jit_begin()`/`__jit_end()`. |
| `05-cosmo-windows-runtime` | Windows run-time fixes: `getrlimit(RLIMIT_NOFILE)` fails (a warning in `os_setup_limits`, and the 9p constructor would exit before `main`; both now tolerate it), the monitor is used before its globals exist, RAM is mapped directly because only whole allocations can be unmapped or `MAP_FIXED`-replaced, a zero block size probe divided by zero, and `O_ASYNC` is all ones. |
| `06-cosmo-enable-whpx` | WHPX for x86_64 guests on the x86_64 slice. `LoadLibrary`/`GetProcAddress` become `cosmo_dlopen`/`cosmo_dlsym` + `cosmo_dltramp` (callbacks stay Microsoft x64), gated on `IsWindows()`. `whpx_send_msi()` drops fixed interrupts below vector 16, which make `WHvRequestInterrupt` fast-fail (`0xC0000409`). Headers: see `compat/whp`. |
| `07-cosmo-enable-hvf` | HVF for aarch64 guests on the aarch64 slice. Hypervisor.framework is loaded with `cosmo_dlopen` and every `hv_*` call goes through a function table (`accel/hvf/hvf-cosmo.c`, header `compat/hvf`). `-cpu host` chooses the KVM or HVF probe at run time, and SME is hidden (HVF cannot run it, and QEMU 9.2 aborts on SME without SVE). `HV_DENIED` explains the missing entitlement. |
| `08-cosmo-windows-create-locking` | Skip the `F_GETLK` check after `raw_co_create()` locks the new file on Windows: Cosmopolitan's `LockFileEx()` emulation counts the fd's own locks as conflicts, so `qemu-img create` failed with `Failed to get "resize" lock`. No protection is lost: native Windows QEMU does no image locking and OFD locks are unavailable. |
| `09-cosmo-windows-paths` | Recognise drive-letter paths, `\\` separators and `\\server` paths in `block.c` when `IsWindows()`; otherwise `C:\...` was read as protocol `C:`. |
| `10-cosmo-sscanf-scansets` | Cosmopolitan's `sscanf()` returns -1 for any `%[...]`, which broke `-monitor tcp:host:port`, `host:port` parsing, `-readconfig`, `-set`/`-global`, QOM paths and vmdk. `osdep.h` redirects to `cosmo_sscanf()` (`compat/scanf`). `fscanf()` is not covered (only `vmsr_energy.c`). |
| `11-cosmo-windows-event-notifier` | `poll()` on a Windows pipe sleeps in 15.6 ms ticks, so the pipe-based `EventNotifier` delayed every main-loop wake-up (CD-ROM reads cost 15.6 ms per 2 KiB). On Windows the notifier is a connected loopback TCP pair, which `WSAPoll()` wakes at once. |
| `12-cosmo-windows-timer-resolution` | The guest's 1 kHz PIT needs ~1 ms main-loop wake-ups, or a Linux guest with `HZ=1000` panics (`IO-APIC + timer doesn't work!`). `NtSetTimerResolution()` does not last, because `clock_nanosleep()` cancels the request when its last sleeper wakes, so `qemu_init_main_loop()` starts a thread that sleeps forever. |
| `13-cosmo-whpx-kick-out-of-hlt` | With the Hyper-V APIC a vCPU halted in `HLT` is not woken by the PIC interrupt queued through `WHvRegisterPendingEvent` (only MSIs wake it), so a bootloader idling in `HLT` hung. Clear `HaltSuspend` on injection, as upstream's `whpx_vcpu_kick_out_of_hlt()` later did. |
| `14-cosmo-pbkdf-thread-cpu` | `RUSAGE_THREAD` is a run-time value here, so LUKS/qcow2 encryption failed with `Unable to calculate thread CPU usage`. Use `clock_gettime(CLOCK_THREAD_CPUTIME_ID)`. |
| `15-cosmo-enable-virtfs` | virtio-9p on the `cosmopolitan` host OS (`hw/9pfs/9p-util-cosmo.c`), decided at run time: errno and device numbers translated off Linux; `mknodat()` and xattrs as raw Linux system calls (xattrs `ENOTSUP` elsewhere, `mknodat()` degrades to a regular file); `O_*` flags go through `HOST_O()` because a missing flag is all ones; `mapped-xattr` refused off Linux. Without `O_NOFOLLOW` (Windows) final-component symlink checks are weaker. |
| `16-cosmo-thread-stack-size` | Cosmopolitan's default thread stack is 64 KiB; the VNC worker keeps a 100 KiB `VncState` on its stack and crashed. `qemu_thread_create()` asks for 2 MiB. |
| `17-cosmo-sdl2-dlopen` | `-display sdl` with SDL2 loaded at run time: `ui/sdl2-cosmo.c` wraps the ~50 SDL functions the 2D renderer calls through `cosmo_dlsym()`/`cosmo_dltramp()`. No audio or OpenGL (SDL audio takes callbacks), and never the default display, so headless hosts keep working. |
| `18-cosmo-sdl2-bundled-library` | On Windows and macOS the executable embeds the official SDL2 (`share/qemu/sdl2/`) and tries it first (on Windows, `SDL2.dll` by name searches the current directory and `PATH`). It is extracted to the user cache directory, named by SHA-256 and reused only if the contents match; written under a temporary name and renamed, 0600 in a 0700 directory, and a symlinked or foreign directory is refused. |

### Building system emulators

The sysroot needs the base Linux kernel headers for the target host architecture, because QEMU's
vendored `linux/kvm.h` includes them (`scripts/lib/headers.sh`). Any `ninja` run after a
`meson.build` change must keep `PKG_CONFIG_PATH`/`PKG_CONFIG_LIBDIR` pointing at the sysroot, or
the regenerated build picks up host libraries.

## `compat/ape`

Hypervisor.framework needs the `com.apple.security.hypervisor` entitlement on the process, which on
Apple Silicon is the loader a Cosmopolitan executable compiles on first run.
`ape-m1-hypervisor.patch` (applied to a copy of cosmocc's `ape-m1.c`) makes the loader sign itself:
it checks its entitlements with `csops`, and if they and the file's (`codesign -d`) lack the
entitlement, it signs a copy with `codesign`, renames it over itself and restarts. Temporary files
are created exclusively and never through a symlink. Failure is silent; QEMU then reports that macOS
denied access when HVF is requested.

`scripts/build.sh` stores the loader as `.q.ape-01` and never uses one from `PATH`, by same-length
edits to two lines of `apelink`'s header script (the build fails if they are not as expected).
Change the loader's number when the loader changes, because a stored loader is reused as is.
