/* SPDX-License-Identifier: MIT */
/* Cosmopolitan's sscanf() returns -1 on any %[...] scanset; including this redirects to cosmo_sscanf(). */
#ifndef COSMO_SSCANF_H
#define COSMO_SSCANF_H

#include <stdio.h>

int cosmo_sscanf(const char *str, const char *fmt, ...);

#define sscanf cosmo_sscanf

#endif
