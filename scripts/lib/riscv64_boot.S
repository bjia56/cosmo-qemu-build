# SPDX-License-Identifier: MIT
# Assembled with `riscv64-linux-gnu-as -march=rv64i` and `objcopy -O binary`; the bytes are in
# scripts/smoke_test_system.sh (riscv64 payload). Position independent, runs in M- or S-mode:
# prints a message on the virt machine's NS16550 UART, then waits for interrupts forever.
    .option norvc
    .text
    .globl _start
_start:
    lui   a0, 0x10000           # a0 = UART base
    auipc a1, 0
    addi  a1, a1, 48            # a1 = msg (48 bytes past the auipc)
1:  lbu   a2, 0(a1)
    beqz  a2, 3f
2:  lbu   a3, 5(a0)             # line status register
    andi  a3, a3, 0x20          # transmitter holding register empty
    beqz  a3, 2b
    sb    a2, 0(a0)
    addi  a1, a1, 1
    j     1b
3:  wfi
    j     3b
msg:
    .asciz "COSMO-RISCV64-BOOT-OK\n"
