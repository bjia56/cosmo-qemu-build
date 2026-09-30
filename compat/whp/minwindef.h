/*
 * Just enough of the Windows base types and macros for the Windows Hypervisor
 * Platform headers (WinHvPlatform.h, WinHvEmulation.h) to compile under
 * cosmopolitan. They include apiset.h, apisetcconv.h, minwindef.h and
 * winapifamily.h from the Windows SDK; this stands in for all four (the other
 * three are staged as empty files by scripts/lib/headers.sh).
 *
 * WINAPI is empty on purpose: WHP entry points are called through pointers
 * that cosmo_dltramp() has already adapted to the System V convention.
 * CALLBACK is the Microsoft x64 convention, because Windows calls it.
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

/* SAL annotations carry no meaning for the compiler */
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

/* the WHP headers ask winapifamily.h which API family they are being built for */
#define WINAPI_PARTITION_DESKTOP 1
#define WINAPI_FAMILY_PARTITION(x) 1

#define SUCCEEDED(hr) (((HRESULT)(hr)) >= 0)
#define FAILED(hr) (((HRESULT)(hr)) < 0)

#endif
