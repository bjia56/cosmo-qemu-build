/* SPDX-License-Identifier: MIT */
/*
 * Stands in for the Windows SDK headers the WHP headers include (apiset.h,
 * apisetcconv.h, minwindef.h, winapifamily.h; the others are staged empty).
 *
 * WINAPI is empty because WHP entry points are called through cosmo_dltramp()
 * pointers (System V); CALLBACK is ms_abi because Windows calls it.
 */
#ifndef COSMO_WHP_MINWINDEF_H
#define COSMO_WHP_MINWINDEF_H

#include <stddef.h>
#include <stdint.h>

typedef int32_t HRESULT;
typedef void VOID;
typedef void *PVOID;
typedef void *HANDLE;
typedef int BOOL, WINBOOL;
typedef uint8_t BYTE, UINT8, UCHAR, BOOLEAN;
typedef uint16_t WORD, UINT16, USHORT, WCHAR;
typedef uint32_t DWORD, UINT32, UINT, ULONG;
typedef int32_t INT32, INT, LONG;
typedef uint64_t UINT64, ULONG64, DWORD64, ULONGLONG;

typedef struct _LUID { DWORD LowPart; LONG HighPart; } LUID;
typedef struct _GUID { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } GUID;
typedef int DEVICE_POWER_STATE;
#define ANYSIZE_ARRAY 1

#define _In_
#define _In_opt_
#define _Out_
#define _Out_opt_
#define _Inout_
#define _In_reads_(n)
#define _In_reads_opt_(n)
#define _In_reads_bytes_(n)
#define _Out_writes_(n)
#define _Out_writes_to_(n, c)
#define _Out_writes_bytes_(n)
#define _Out_writes_bytes_to_(n, c)
#define _Out_writes_bytes_to_opt_(n, c)
#define _Outptr_result_buffer_(n)
#ifndef _AMD64_
#define _AMD64_ 1
#endif

#define WINAPI
#define __stdcall
#define CALLBACK __attribute__((ms_abi))
#define DECLSPEC_ALIGN(x) __attribute__((aligned(x)))

#define DEFINE_ENUM_FLAG_OPERATORS(t)
#define C_ASSERT(e) _Static_assert(e, #e)

#define S_OK ((HRESULT)0)
#define RTL_NUMBER_OF(a) (sizeof(a) / sizeof((a)[0]))
#ifndef max
#define max(a, b) (((a) > (b)) ? (a) : (b))
#endif

#define WINAPI_PARTITION_DESKTOP 1
#define WINAPI_FAMILY_PARTITION(x) 1

#define SUCCEEDED(hr) (((HRESULT)(hr)) >= 0)
#define FAILED(hr) (((HRESULT)(hr)) < 0)

#endif
