/* SPDX-License-Identifier: MIT */
/*
 * Cosmopolitan Libc's sscanf() has no %[...] conversion: every scanset makes
 * it return -1. cosmo_sscanf() adds scansets; see cosmo-sscanf.c. Including
 * this header redirects sscanf() to it.
 */
#ifndef COSMO_SSCANF_H
#define COSMO_SSCANF_H

#include <stdio.h>

int cosmo_sscanf(const char *str, const char *fmt, ...);

#define sscanf cosmo_sscanf

#endif
