// SPDX-License-Identifier: MIT
// Global stack protector canary for -fstack-protector -mstack-protector-guard=global.
//
// The default canary location does not work under cosmocc:
//   x86_64   %fs:0x28, but constructors run before TLS is set up (the first protected
//            function dereferences a null %fs base).
//   aarch64  GCC reads a global __stack_chk_guard, which cosmocc's libc does not define.
// libcosmo's x86_64 stackchkguard.o does define it, but its _init___stack_chk_guard stub
// stores through %rdi in the startup chain and corrupts a return address (crash in
// __rlimit_stack_init). Defining the symbol here keeps that object from being linked.
//
// Link this file as an object (not from an archive) and compile it with
// -fno-stack-protector. __stack_chk_fail comes from cosmocc's libc.

#include <stddef.h>
#include <stdint.h>
#include <sys/random.h>

// Non-zero default, used only if getrandom() fails.
uintptr_t __stack_chk_guard = (uintptr_t)0x595e9fbd94fda766ull;

// The first user constructor: nothing protected is live across this call.
__attribute__((constructor(101), no_stack_protector))
static void cosmo_ssp_init(void)
{
    uintptr_t guard = 0;
    size_t got = 0;

    while (got < sizeof(guard)) {
        ssize_t n = getrandom((char *)&guard + got, sizeof(guard) - got, 0);
        if (n <= 0) {
            return; // keep the static value rather than a half-filled one
        }
        got += (size_t)n;
    }
    // a NUL byte stops string-based overflows (str*cpy) from rewriting the canary
    guard &= ~(uintptr_t)0xff;
    __stack_chk_guard = guard;
}
