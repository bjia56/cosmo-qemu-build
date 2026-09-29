/*
 * Just enough of the Windows base types for the Windows Hypervisor Platform
 * headers (winhvplatform.h, winhvemulation.h) to compile under cosmopolitan.
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
typedef int8_t INT8;
typedef int16_t INT16;
typedef int32_t INT32, INT, LONG;
typedef uint64_t UINT64, ULONG64, DWORD64, ULONGLONG;
typedef int64_t INT64, LONG64, LONGLONG;
typedef size_t SIZE_T;

typedef struct _LUID { DWORD LowPart; LONG HighPart; } LUID;
typedef struct _GUID { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } GUID;
typedef int DEVICE_POWER_STATE;
#define ANYSIZE_ARRAY 1

#define WINAPI
#define CALLBACK __attribute__((ms_abi))
#define DECLSPEC_IMPORT
#define DECLSPEC_ALIGN(x) __attribute__((aligned(x)))

#define __C89_NAMELESS
#define DEFINE_ENUM_FLAG_OPERATORS(t)
#define C_ASSERT(e) _Static_assert(e, #e)

#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif

#define S_OK ((HRESULT)0)
#define S_FALSE ((HRESULT)1)
#define RTL_NUMBER_OF(a) (sizeof(a) / sizeof((a)[0]))
#ifndef max
#define max(a, b) (((a) > (b)) ? (a) : (b))
#endif
#ifndef min
#define min(a, b) (((a) < (b)) ? (a) : (b))
#endif

#define SUCCEEDED(hr) (((HRESULT)(hr)) >= 0)
#define FAILED(hr) (((HRESULT)(hr)) < 0)

#endif
