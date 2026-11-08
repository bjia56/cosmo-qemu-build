# shellcheck shell=sh
# SPDX-License-Identifier: MIT
# The guest architectures this project builds system emulators for, and the firmware each one embeds.
# POSIX sh: sourced by scripts/build.sh, scripts/smoke_test_all.sh and the CI workflow.
#
# Adding a guest: add it to SUPPORTED_GUESTS and to guest_firmware_regex, give it a case in
# scripts/smoke_test_system.sh, and add its upload step to .github/workflows/build.yml.

# Order matters only for output: the first one is also the guest the -sandbox test runs.
SUPPORTED_GUESTS="x86_64 aarch64 riscv64 ppc"

# guest_firmware_regex <guest>: regex of the files under share/qemu to embed for <guest>
guest_firmware_regex() {
    case "$1" in
        x86_64) echo '^(bios(-256k|-microvm)?\.bin|qboot\.rom|vgabios.*\.bin|kvmvapic\.bin|linuxboot(_dma)?\.bin|multiboot(_dma)?\.bin|pvh\.bin|sgabios\.bin|efi-.*\.rom|edk2-(x86_64|i386)-.*\.fd|edk2-licenses\.txt|firmware/.*(x86_64|i386).*\.json|keymaps/.+)$' ;;
        aarch64) echo '^(vgabios.*\.bin|efi-.*\.rom|edk2-aarch64-.*\.fd|edk2-licenses\.txt|firmware/.*aarch64.*\.json|keymaps/.+)$' ;;
        # OpenSBI is the default -bios of the virt machine; edk2 runs on top of it from pflash
        # (QEMU 9.2 ships no firmware descriptor for it)
        riscv64) echo '^(opensbi-riscv64-generic-fw_dynamic\.bin|vgabios.*\.bin|efi-.*\.rom|edk2-riscv-.*\.fd|edk2-licenses\.txt|keymaps/.+)$' ;;
        # OpenBIOS for the Macs (g3beige, mac99) with the Mac OS VGA driver it hands on, VOF for
        # pegasos2, U-Boot for ppce500 and sam460ex, device trees for bamboo and sam460ex
        ppc) echo '^(openbios-ppc|qemu_vga\.ndrv|vof\.bin|u-boot\.e500|u-boot-sam460-.*\.bin|(bamboo|canyonlands)\.dtb|vgabios.*\.bin|efi-.*\.rom|keymaps/.+)$' ;;
        *) return 1 ;;
    esac
}

# is_supported_guest <guest>
is_supported_guest() {
    case " ${SUPPORTED_GUESTS} " in *" $1 "*) return 0 ;; esac
    return 1
}
