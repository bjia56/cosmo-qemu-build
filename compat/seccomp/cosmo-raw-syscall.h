/* SPDX-License-Identifier: MIT */
/*
 * Raw Linux system calls for libseccomp and QEMU's seccomp code.
 *
 * Cosmopolitan's syscall() is a stub that translates only gettid, getrandom and
 * getcpu and fails everything else with ENOSYS, so seccomp(2) (TSYNC, action
 * probing) would never be reached. The numbers passed here are Linux's, taken
 * from the kernel headers at compile time, so the call is made directly and
 * only when running on Linux.
 */
#ifndef COSMO_RAW_SYSCALL_H
#define COSMO_RAW_SYSCALL_H

#include <cosmo.h>
#include <errno.h>

static inline long cosmo_raw_syscall(long nr, long a1, long a2, long a3,
                                     long a4, long a5, long a6)
{
    long ret;

    if (!IsLinux()) {
        errno = ENOSYS;
        return -1;
    }
#if defined(__x86_64__)
    register long r10 __asm__("r10") = a4;
    register long r8 __asm__("r8") = a5;
    register long r9 __asm__("r9") = a6;
    __asm__ volatile("syscall"
                     : "=a"(ret)
                     : "0"(nr), "D"(a1), "S"(a2), "d"(a3), "r"(r10), "r"(r8), "r"(r9)
                     : "rcx", "r11", "memory");
#elif defined(__aarch64__)
    register long x8 __asm__("x8") = nr;
    register long x0 __asm__("x0") = a1;
    register long x1 __asm__("x1") = a2;
    register long x2 __asm__("x2") = a3;
    register long x3 __asm__("x3") = a4;
    register long x4 __asm__("x4") = a5;
    register long x5 __asm__("x5") = a6;
    __asm__ volatile("svc 0"
                     : "+r"(x0)
                     : "r"(x8), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5)
                     : "memory", "cc");
    ret = x0;
#else
#error "unsupported architecture"
#endif
    if ((unsigned long)ret > (unsigned long)-4096L) {
        errno = (int)-ret;
        return -1;
    }
    return ret;
}

#endif /* COSMO_RAW_SYSCALL_H */
