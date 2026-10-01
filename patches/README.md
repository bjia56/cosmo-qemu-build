# Patches

Cosmopolitan-specific changes applied on top of upstream sources by
`scripts/build.sh`. Patches are grouped by component and upstream
version, and applied in filename order. Each patch is one topic, so
moving to a newer upstream means resolving conflicts one topic at a time.

## `glib/2.82.4`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-portability` | `O_NONBLOCK`, `POLL*` and `AF_*`/`MSG_*` are runtime values under Cosmopolitan: drop the compile-time `O_NONBLOCK` assertion, fall back to the Linux constants for `glibconfig.h` when the build-time probe cannot compute them, and translate `G_IO_*` to and from the runtime `POLL*` values around `poll()` (they differ on Windows). |

## `libslirp/4.9.3`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-portability` | Cosmopolitan has no `if_nametoindex()`: ignore the interface scope of a `nameserver fe80::1%eth0` line in `resolv.conf` instead of resolving it. |
| `02-cosmo-sscanf-scansets` | The same `sscanf()` replacement as QEMU's patch `10` (`compat/scanf`) for libslirp's `resolv.conf` parsing (`nameserver%*[ \t]%256s`) and its FTP and IRC helpers. |

## `qemu/v9.2.0`

| Patch | Purpose |
| --- | --- |
| `01-cosmo-portability` | Detect Cosmopolitan in `configure` and use a distinct `cosmopolitan` host OS, so QEMU takes its portable POSIX paths instead of Linux-only ones (raw futex, `linux/*.h`). Then the run-time-value and missing-definition workarounds: `MAP_SYNC`/`MAP_SHARED_VALIDATE`/`TMPFS_MAGIC` without `linux/*.h`; `G_IO_*` translation in `qemu_poll_ns()`; the smallest `IOV_MAX` of any OS (16, Windows) for the migration `iovec` array; `IPPROTO_ESP`/`IPPROTO_AH`. |
| `02-cosmo-mcosmo` | The build compiles QEMU with `-mcosmo` (`_COSMO_SOURCE`). Call `ShowCrashReports()` at the start of `main()` (registers, a backtrace and a `cosmoaddr2line` command instead of a bare "terminating on uncaught signal"), and fix the two names `-mcosmo` collides with: the static `startswith()` in `gdbstub.c` (renamed) and the `rdrand` TCG helper (`#undef rdrand` in `translate.c` and `int_helper.c`, so it keeps one name in both). |
| `03-cosmo-enable-kvm` | Allow the KVM accelerator on the `cosmopolitan` host OS: meson gates, vendored `linux-headers` include path and `asm` symlink, `arch_prctl` via raw Linux system calls (`include/qemu/cosmo-linux-syscall.h`, guarded by `IsLinux()`), a real `eventfd2` in `EventNotifier` (a pipe elsewhere), kernel-typed `VMSTATE_*` macros, and Xen emulation off by default. KVM is only usable at run time on Linux; elsewhere `/dev/kvm` cannot be opened and QEMU falls back to the next accelerator. |
| `04-cosmo-aarch64-host` | aarch64 TCG on Cosmopolitan: `x28` holds Cosmopolitan's thread-local storage base, so the TCG backend must not allocate it (seen as a segfault in `rcu_read_lock()`). On macOS, reading `CTR_EL0` raises `SIGILL` (a crash before `main()`), so skip it outside Linux (line sizes fall back to `sysconf`/64) and flush through Cosmopolitan's `__clear_cache()`; and map the code buffer with `MAP_JIT` and use `__jit_begin()`/`__jit_end()` for the per-thread write/execute toggle (both no-ops elsewhere). |
| `05-cosmo-windows-runtime` | Windows-only run-time fixes. `getrlimit(RLIMIT_NOFILE)` fails with `EINVAL`, which made `os_setup_limits()` warn before the monitor's globals existed (uninitialized mutex): skip that warning and make `monitor_cur()` safe early. Cosmopolitan can only unmap or `MAP_FIXED`-replace whole allocations on Windows, so map RAM directly there. A block-size probe reporting success with zero sizes divided by zero in `blkconf_blocksizes()`: ignore it with a warning. An `O_*` flag a system lacks is all ones, not zero (`O_ASYNC` is `0xffffffff` on Windows), so skip the `O_ASYNC` assertion in `raw_reconfigure_getfd()`. |
| `06-cosmo-enable-whpx` | WHPX for x86_64 guests on the x86_64 host slice. `LoadLibrary`/`GetProcAddress` become `cosmo_dlopen`/`cosmo_dlsym` + `cosmo_dltramp` (entry points are called through System V trampolines, emulator callbacks stay Microsoft x64 `CALLBACK`), the load is gated on `IsWindows()`, `HRESULT` constants and diagnostics are fixed for LP64, and the meson gate accepts the `cosmopolitan` host OS. `WHvRequestInterrupt` fast-fails (`0xC0000409`) on a fixed interrupt below vector 16, which the guest's startup produces once with the in-kernel APIC, so `whpx_send_msi()` drops those. The WHP headers are Microsoft's MIT-licensed ones, fetched at build time; `compat/whp/minwindef.h` supplies the few base Windows types and macros they need. |
| `07-cosmo-enable-hvf` | HVF for aarch64 guests on the aarch64 host slice. `Hypervisor.framework` is loaded with `cosmo_dlopen` when the accelerator initializes (`accel/hvf/hvf-cosmo.c`), and every `hv_*` call (plus `mach_absolute_time` and `os_release` from libSystem) goes through a function table, so nothing links against the framework. The header QEMU includes is `compat/hvf/Hypervisor/Hypervisor.h`, a minimal interface written for this build; the meson gate accepts the `cosmopolitan` host OS on aarch64. `-cpu host` picks the KVM or HVF feature probe at run time (upstream chooses at compile time, and this build has both), the host-feature probe reports which step failed and hides SME (newer Apple SoCs report it, HVF cannot run it, and QEMU 9.2 aborts on SME without SVE). Initialization fails cleanly off Apple Silicon, and an `HV_DENIED` result explains the missing `com.apple.security.hypervisor` entitlement. |
| `08-cosmo-windows-create-locking` | `raw_co_create()` takes byte-range locks on the new file and then probes them with `F_GETLK`, unconditionally (not gated on `locking=`). Cosmopolitan emulates `F_GETLK` on Windows with `LockFileEx()`, which counts the fd's own locks as conflicts, so `qemu-img create` failed with `Failed to get "resize" lock`. Skip that check on Windows. This does not reduce protection compared with upstream: native Windows QEMU (`file-win32.c`) does no image locking, and `locking=auto` is already off in this build because Windows has no OFD locks (`F_OFD_*` is `-1`). |
| `09-cosmo-windows-paths` | Cosmopolitan's `open()` accepts Windows paths (`C:\dir\file`, either slash) on Windows, but QEMU only knows about drive letters and backslashes under `_WIN32`, so `-drive file=C:\...` or `qemu-img create C:\...` was read as protocol `C:` ("Unknown protocol"). `path_has_protocol()`, `path_is_absolute()` and `path_combine()` in `block.c` now recognise drive-letter paths, `\\` separators and `\\server` paths when `IsWindows()`; behaviour elsewhere is unchanged. |
| `10-cosmo-sscanf-scansets` | Cosmopolitan's `sscanf()` has no `%[...]` conversion: every scanset makes it return -1, which broke the legacy chardev shorthands (`-monitor tcp:host:port`, `vc:80Cx24C`), `host:port` parsing in `qemu-sockets.c`, `-readconfig`, `-set`/`-global`, QOM path lookup and vmdk descriptors. `osdep.h` redirects `sscanf` to `cosmo_sscanf()` (`compat/scanf`, copied into `util/` and `include/qemu/` by the build). It handles scansets itself and passes every other conversion to libc. `fscanf()` is not covered (only `vmsr_energy.c`, KVM RAPL). |
| `11-cosmo-windows-event-notifier` | On Windows Cosmopolitan's `poll()` cannot wait for data on a pipe: it peeks the pipe and sleeps `POLL_INTERVAL_MS` (10 ms, rounded up to Windows' 15.6 ms timer tick), and it does the same for the named pipes behind `socketpair()`. QEMU's `EventNotifier` falls back to a pipe without `eventfd`, so the main loop noticed each wake-up (every completed thread-pool block request, among others) only once per tick: reading a CD-ROM image cost 15.6 ms per 2 KiB, and Alpine's ISO took minutes to load a kernel that takes seconds elsewhere. On Windows the notifier is now a connected loopback TCP pair, which `poll()` waits on in `WSAPoll()` and which wakes at once. |
| `12-cosmo-windows-timer-resolution` | Windows rounds every timed wait up to its 15.6 ms tick, and the guest's 1 kHz PIT needs the main loop to wake about every millisecond: a Linux guest with `HZ=1000` (Alpine's) panics at boot with `IO-APIC + timer doesn't work!` otherwise, and then spins in `mdelay()` with no output. Asking for a finer resolution with `NtSetTimerResolution()` does not last, because Cosmopolitan's `clock_nanosleep()` requests the finest resolution for each sleep and then cancels the process's request when the last sleeper wakes. It only does that when no other thread is sleeping, so `qemu_init_main_loop()` starts a thread that sleeps for the life of the process, which keeps the finest resolution (0.5 ms) in place. |
| `13-cosmo-whpx-kick-out-of-hlt` | With the Hyper-V APIC (`kernel-irqchip=on`, the default) a vCPU that has executed `HLT` stays halted inside the hypervisor. Interrupts requested with `WHvRequestInterrupt` (MSIs: the IO-APIC and the LAPIC timer) wake it, but the external interrupt that `whpx_vcpu_pre_run()` queues for the PIC through `WHvRegisterPendingEvent` does not. A BIOS or bootloader that idles in `HLT` (ISOLINUX at its `boot:` prompt, via SeaBIOS) therefore never saw a timer tick and sat there forever with IRQ0 in service in the PIC, at ~0% CPU; Linux, which uses the IO-APIC, was unaffected. The halt state (`HaltSuspend` in `WHvRegisterInternalActivityState`) is now cleared when such an interrupt is injected, as upstream QEMU later did in `whpx_vcpu_kick_out_of_hlt()`. |
| `14-cosmo-pbkdf-thread-cpu` | LUKS and qcow2 encryption benchmark the key-derivation function against the thread's CPU time, and `qemu-img create -f luks` failed with `Unable to calculate thread CPU usage on this platform`. `crypto/pbkdf.c` only knew `_WIN32`, macOS and `RUSAGE_THREAD`, which is a run-time value here (not a macro). Use `clock_gettime(CLOCK_THREAD_CPUTIME_ID)` under Cosmopolitan, which works on every host OS. |

Patches `03`-`07` are only needed for the system emulators; they are harmless
for the `qemu-img` build.

### Building system emulators

System emulators additionally need the base Linux kernel headers (`linux/types.h`,
`linux/ioctl.h`, ... and `asm-generic/*`, plus the per-architecture `asm/*`) for the target
host architecture in the sysroot, because QEMU's vendored `linux/kvm.h` includes them
(`linux-libc-dev`, and `linux-libc-dev-arm64-cross` for aarch64). Do not copy the kernel's
own `kvm.h` there; QEMU's vendored copy must win. Any `ninja` run after a `meson.build`
change must keep `PKG_CONFIG_PATH`/`PKG_CONFIG_LIBDIR` pointing at the sysroot, or the
regenerated build picks up host libraries.

## `compat/ape`

Hypervisor.framework only works for a process whose executable has the `com.apple.security.hypervisor`
entitlement. On Apple Silicon that process is the small loader a Cosmopolitan executable compiles on its
first run and stores in `${TMPDIR:-$HOME}`. `ape-m1-hypervisor.patch` is applied by `scripts/build.sh` to a
copy of cosmocc's `ape-m1.c` (the source of that loader) so that the loader signs itself, transparently:

- On startup it asks the kernel for its own entitlements (`csops`). If the hypervisor entitlement is there,
  it carries on: the normal case costs one system call.
- If not, and the loader file on disk does not have the entitlement either (`codesign -d`), it copies itself,
  ad-hoc signs the copy with the entitlement using `codesign`, renames the copy over the loader (running
  instances keep their file) and starts again.
- Its temporary files (the copy and the entitlements list) are created exclusively and never through a
  symlink.
- Signing is silent. If it fails, nothing is printed; QEMU reports that macOS denied access to
  Hypervisor.framework when HVF is requested.

The executables store this loader as `.q.ape-01`, and a loader found in `PATH` is never used, so no other
program's loader can stand in for the signed one. This is done by `scripts/build.sh` with same-length
replacements in two lines of the shell script that `apelink` writes at the start of each file (the build
fails if those lines are not exactly as expected). Change the loader's number when the loader changes,
because a stored loader is reused as is.
