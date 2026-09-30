/*
 * Minimal Hypervisor.framework (Apple Silicon) interface for building QEMU's
 * HVF accelerator under Cosmopolitan libc, where the framework cannot be
 * linked. It carries only the types, constants and prototypes QEMU uses,
 * written from the documented ABI, and routes every hv_*() call through a
 * table that is filled in at run time with cosmo_dlopen()/cosmo_dlsym().
 */
#ifndef COSMO_HYPERVISOR_H
#define COSMO_HYPERVISOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef int32_t hv_return_t;
#define HV_SUCCESS       ((hv_return_t)0)
#define HV_ERROR         ((hv_return_t)0xfae94001)
#define HV_BUSY          ((hv_return_t)0xfae94002)
#define HV_BAD_ARGUMENT  ((hv_return_t)0xfae94003)
#define HV_NO_RESOURCES  ((hv_return_t)0xfae94005)
#define HV_NO_DEVICE     ((hv_return_t)0xfae94006)
#define HV_DENIED        ((hv_return_t)0xfae94007)
#define HV_UNSUPPORTED   ((hv_return_t)0xfae9400f)

typedef uint64_t hv_ipa_t;
typedef uint64_t hv_vcpu_t;
typedef uint64_t hv_memory_flags_t;
typedef struct hv_vm_config_s *hv_vm_config_t;
typedef struct hv_vcpu_config_s *hv_vcpu_config_t;

#define HV_MEMORY_READ   (1ull << 0)
#define HV_MEMORY_WRITE  (1ull << 1)
#define HV_MEMORY_EXEC   (1ull << 2)

typedef uint32_t hv_exit_reason_t;
#define HV_EXIT_REASON_CANCELED         ((hv_exit_reason_t)0)
#define HV_EXIT_REASON_EXCEPTION        ((hv_exit_reason_t)1)
#define HV_EXIT_REASON_VTIMER_ACTIVATED ((hv_exit_reason_t)2)

typedef struct {
    uint64_t syndrome;
    uint64_t virtual_address;
    hv_ipa_t physical_address;
} hv_vcpu_exit_exception_t;

typedef struct {
    hv_exit_reason_t reason;
    hv_vcpu_exit_exception_t exception;
} hv_vcpu_exit_t;

/* 128-bit SIMD&FP register, passed in a vector register by the AAPCS64 */
typedef uint8_t hv_simd_fp_uchar16_t __attribute__((vector_size(16)));

typedef uint32_t hv_reg_t;
typedef uint32_t hv_simd_fp_reg_t;
typedef uint32_t hv_sys_reg_t;
typedef uint32_t hv_feature_reg_t;
typedef uint32_t hv_interrupt_type_t;

enum {
    HV_REG_X0 = 0,
    HV_REG_X1 = 1,
    HV_REG_X2 = 2,
    HV_REG_X3 = 3,
    HV_REG_X4 = 4,
    HV_REG_X5 = 5,
    HV_REG_X6 = 6,
    HV_REG_X7 = 7,
    HV_REG_X8 = 8,
    HV_REG_X9 = 9,
    HV_REG_X10 = 10,
    HV_REG_X11 = 11,
    HV_REG_X12 = 12,
    HV_REG_X13 = 13,
    HV_REG_X14 = 14,
    HV_REG_X15 = 15,
    HV_REG_X16 = 16,
    HV_REG_X17 = 17,
    HV_REG_X18 = 18,
    HV_REG_X19 = 19,
    HV_REG_X20 = 20,
    HV_REG_X21 = 21,
    HV_REG_X22 = 22,
    HV_REG_X23 = 23,
    HV_REG_X24 = 24,
    HV_REG_X25 = 25,
    HV_REG_X26 = 26,
    HV_REG_X27 = 27,
    HV_REG_X28 = 28,
    HV_REG_X29 = 29,
    HV_REG_X30 = 30,
    HV_REG_PC = 31,
    HV_REG_FPCR = 32,
    HV_REG_FPSR = 33,
    HV_REG_CPSR = 34,
};

enum {
    HV_SIMD_FP_REG_Q0 = 0,
    HV_SIMD_FP_REG_Q1 = 1,
    HV_SIMD_FP_REG_Q2 = 2,
    HV_SIMD_FP_REG_Q3 = 3,
    HV_SIMD_FP_REG_Q4 = 4,
    HV_SIMD_FP_REG_Q5 = 5,
    HV_SIMD_FP_REG_Q6 = 6,
    HV_SIMD_FP_REG_Q7 = 7,
    HV_SIMD_FP_REG_Q8 = 8,
    HV_SIMD_FP_REG_Q9 = 9,
    HV_SIMD_FP_REG_Q10 = 10,
    HV_SIMD_FP_REG_Q11 = 11,
    HV_SIMD_FP_REG_Q12 = 12,
    HV_SIMD_FP_REG_Q13 = 13,
    HV_SIMD_FP_REG_Q14 = 14,
    HV_SIMD_FP_REG_Q15 = 15,
    HV_SIMD_FP_REG_Q16 = 16,
    HV_SIMD_FP_REG_Q17 = 17,
    HV_SIMD_FP_REG_Q18 = 18,
    HV_SIMD_FP_REG_Q19 = 19,
    HV_SIMD_FP_REG_Q20 = 20,
    HV_SIMD_FP_REG_Q21 = 21,
    HV_SIMD_FP_REG_Q22 = 22,
    HV_SIMD_FP_REG_Q23 = 23,
    HV_SIMD_FP_REG_Q24 = 24,
    HV_SIMD_FP_REG_Q25 = 25,
    HV_SIMD_FP_REG_Q26 = 26,
    HV_SIMD_FP_REG_Q27 = 27,
    HV_SIMD_FP_REG_Q28 = 28,
    HV_SIMD_FP_REG_Q29 = 29,
    HV_SIMD_FP_REG_Q30 = 30,
    HV_SIMD_FP_REG_Q31 = 31,
};

enum {
    HV_INTERRUPT_TYPE_IRQ = 0,
    HV_INTERRUPT_TYPE_FIQ = 1,
};

enum {
    HV_FEATURE_REG_ID_AA64DFR0_EL1 = 0,
};

/*
 * System register identifiers are the Arm architectural encodings,
 * op0<<14 | op1<<11 | CRn<<7 | CRm<<3 | op2, the same tuples QEMU's
 * hvf_sreg_match table (target/arm/hvf/hvf.c) lists for these registers.
 */
enum {
    HV_SYS_REG_AFSR0_EL1 = 0xc288,
    HV_SYS_REG_AFSR1_EL1 = 0xc289,
    HV_SYS_REG_AMAIR_EL1 = 0xc518,
    HV_SYS_REG_APDAKEYHI_EL1 = 0xc111,
    HV_SYS_REG_APDAKEYLO_EL1 = 0xc110,
    HV_SYS_REG_APDBKEYHI_EL1 = 0xc113,
    HV_SYS_REG_APDBKEYLO_EL1 = 0xc112,
    HV_SYS_REG_APGAKEYHI_EL1 = 0xc119,
    HV_SYS_REG_APGAKEYLO_EL1 = 0xc118,
    HV_SYS_REG_APIAKEYHI_EL1 = 0xc109,
    HV_SYS_REG_APIAKEYLO_EL1 = 0xc108,
    HV_SYS_REG_APIBKEYHI_EL1 = 0xc10b,
    HV_SYS_REG_APIBKEYLO_EL1 = 0xc10a,
    HV_SYS_REG_CNTKCTL_EL1 = 0xc708,
    HV_SYS_REG_CNTV_CTL_EL0 = 0xdf19,
    HV_SYS_REG_CNTV_CVAL_EL0 = 0xdf1a,
    HV_SYS_REG_CONTEXTIDR_EL1 = 0xc681,
    HV_SYS_REG_CPACR_EL1 = 0xc082,
    HV_SYS_REG_CSSELR_EL1 = 0xd000,
    HV_SYS_REG_DBGBCR0_EL1 = 0x8005,
    HV_SYS_REG_DBGBCR10_EL1 = 0x8055,
    HV_SYS_REG_DBGBCR11_EL1 = 0x805d,
    HV_SYS_REG_DBGBCR12_EL1 = 0x8065,
    HV_SYS_REG_DBGBCR13_EL1 = 0x806d,
    HV_SYS_REG_DBGBCR14_EL1 = 0x8075,
    HV_SYS_REG_DBGBCR15_EL1 = 0x807d,
    HV_SYS_REG_DBGBCR1_EL1 = 0x800d,
    HV_SYS_REG_DBGBCR2_EL1 = 0x8015,
    HV_SYS_REG_DBGBCR3_EL1 = 0x801d,
    HV_SYS_REG_DBGBCR4_EL1 = 0x8025,
    HV_SYS_REG_DBGBCR5_EL1 = 0x802d,
    HV_SYS_REG_DBGBCR6_EL1 = 0x8035,
    HV_SYS_REG_DBGBCR7_EL1 = 0x803d,
    HV_SYS_REG_DBGBCR8_EL1 = 0x8045,
    HV_SYS_REG_DBGBCR9_EL1 = 0x804d,
    HV_SYS_REG_DBGBVR0_EL1 = 0x8004,
    HV_SYS_REG_DBGBVR10_EL1 = 0x8054,
    HV_SYS_REG_DBGBVR11_EL1 = 0x805c,
    HV_SYS_REG_DBGBVR12_EL1 = 0x8064,
    HV_SYS_REG_DBGBVR13_EL1 = 0x806c,
    HV_SYS_REG_DBGBVR14_EL1 = 0x8074,
    HV_SYS_REG_DBGBVR15_EL1 = 0x807c,
    HV_SYS_REG_DBGBVR1_EL1 = 0x800c,
    HV_SYS_REG_DBGBVR2_EL1 = 0x8014,
    HV_SYS_REG_DBGBVR3_EL1 = 0x801c,
    HV_SYS_REG_DBGBVR4_EL1 = 0x8024,
    HV_SYS_REG_DBGBVR5_EL1 = 0x802c,
    HV_SYS_REG_DBGBVR6_EL1 = 0x8034,
    HV_SYS_REG_DBGBVR7_EL1 = 0x803c,
    HV_SYS_REG_DBGBVR8_EL1 = 0x8044,
    HV_SYS_REG_DBGBVR9_EL1 = 0x804c,
    HV_SYS_REG_DBGWCR0_EL1 = 0x8007,
    HV_SYS_REG_DBGWCR10_EL1 = 0x8057,
    HV_SYS_REG_DBGWCR11_EL1 = 0x805f,
    HV_SYS_REG_DBGWCR12_EL1 = 0x8067,
    HV_SYS_REG_DBGWCR13_EL1 = 0x806f,
    HV_SYS_REG_DBGWCR14_EL1 = 0x8077,
    HV_SYS_REG_DBGWCR15_EL1 = 0x807f,
    HV_SYS_REG_DBGWCR1_EL1 = 0x800f,
    HV_SYS_REG_DBGWCR2_EL1 = 0x8017,
    HV_SYS_REG_DBGWCR3_EL1 = 0x801f,
    HV_SYS_REG_DBGWCR4_EL1 = 0x8027,
    HV_SYS_REG_DBGWCR5_EL1 = 0x802f,
    HV_SYS_REG_DBGWCR6_EL1 = 0x8037,
    HV_SYS_REG_DBGWCR7_EL1 = 0x803f,
    HV_SYS_REG_DBGWCR8_EL1 = 0x8047,
    HV_SYS_REG_DBGWCR9_EL1 = 0x804f,
    HV_SYS_REG_DBGWVR0_EL1 = 0x8006,
    HV_SYS_REG_DBGWVR10_EL1 = 0x8056,
    HV_SYS_REG_DBGWVR11_EL1 = 0x805e,
    HV_SYS_REG_DBGWVR12_EL1 = 0x8066,
    HV_SYS_REG_DBGWVR13_EL1 = 0x806e,
    HV_SYS_REG_DBGWVR14_EL1 = 0x8076,
    HV_SYS_REG_DBGWVR15_EL1 = 0x807e,
    HV_SYS_REG_DBGWVR1_EL1 = 0x800e,
    HV_SYS_REG_DBGWVR2_EL1 = 0x8016,
    HV_SYS_REG_DBGWVR3_EL1 = 0x801e,
    HV_SYS_REG_DBGWVR4_EL1 = 0x8026,
    HV_SYS_REG_DBGWVR5_EL1 = 0x802e,
    HV_SYS_REG_DBGWVR6_EL1 = 0x8036,
    HV_SYS_REG_DBGWVR7_EL1 = 0x803e,
    HV_SYS_REG_DBGWVR8_EL1 = 0x8046,
    HV_SYS_REG_DBGWVR9_EL1 = 0x804e,
    HV_SYS_REG_ELR_EL1 = 0xc201,
    HV_SYS_REG_ESR_EL1 = 0xc290,
    HV_SYS_REG_FAR_EL1 = 0xc300,
    HV_SYS_REG_ID_AA64DFR0_EL1 = 0xc028,
    HV_SYS_REG_ID_AA64DFR1_EL1 = 0xc029,
    HV_SYS_REG_ID_AA64ISAR0_EL1 = 0xc030,
    HV_SYS_REG_ID_AA64ISAR1_EL1 = 0xc031,
    HV_SYS_REG_ID_AA64MMFR0_EL1 = 0xc038,
    HV_SYS_REG_ID_AA64MMFR1_EL1 = 0xc039,
    HV_SYS_REG_ID_AA64MMFR2_EL1 = 0xc03a,
    HV_SYS_REG_ID_AA64PFR0_EL1 = 0xc020,
    HV_SYS_REG_ID_AA64PFR1_EL1 = 0xc021,
    HV_SYS_REG_MAIR_EL1 = 0xc510,
    HV_SYS_REG_MDCCINT_EL1 = 0x8010,
    HV_SYS_REG_MDSCR_EL1 = 0x8012,
    HV_SYS_REG_MIDR_EL1 = 0xc000,
    HV_SYS_REG_MPIDR_EL1 = 0xc005,
    HV_SYS_REG_PAR_EL1 = 0xc3a0,
    HV_SYS_REG_SCTLR_EL1 = 0xc080,
    HV_SYS_REG_SPSR_EL1 = 0xc200,
    HV_SYS_REG_SP_EL0 = 0xc208,
    HV_SYS_REG_SP_EL1 = 0xe208,
    HV_SYS_REG_TCR_EL1 = 0xc102,
    HV_SYS_REG_TPIDRRO_EL0 = 0xde83,
    HV_SYS_REG_TPIDR_EL0 = 0xde82,
    HV_SYS_REG_TPIDR_EL1 = 0xc684,
    HV_SYS_REG_TTBR0_EL1 = 0xc100,
    HV_SYS_REG_TTBR1_EL1 = 0xc101,
    HV_SYS_REG_VBAR_EL1 = 0xc600,
};

/*
 * Functions of the framework, resolved at run time. X(return type, name,
 * parameters)
 */
#define HVF_FUNCTIONS(X) \
    X(hv_return_t, hv_vm_create, (hv_vm_config_t config)) \
    X(hv_return_t, hv_vm_map, (void *addr, hv_ipa_t ipa, size_t size, hv_memory_flags_t flags)) \
    X(hv_return_t, hv_vm_unmap, (hv_ipa_t ipa, size_t size)) \
    X(hv_return_t, hv_vm_protect, (hv_ipa_t ipa, size_t size, hv_memory_flags_t flags)) \
    X(hv_vm_config_t, hv_vm_config_create, (void)) \
    X(hv_return_t, hv_vm_config_get_max_ipa_size, (uint32_t *ipa_bit_length)) \
    X(hv_return_t, hv_vm_config_get_default_ipa_size, (uint32_t *ipa_bit_length)) \
    X(hv_return_t, hv_vm_config_set_ipa_size, (hv_vm_config_t config, uint32_t ipa_bit_length)) \
    X(hv_return_t, hv_vcpu_create, (hv_vcpu_t *vcpu, hv_vcpu_exit_t **exit, hv_vcpu_config_t config)) \
    X(hv_return_t, hv_vcpu_destroy, (hv_vcpu_t vcpu)) \
    X(hv_return_t, hv_vcpu_run, (hv_vcpu_t vcpu)) \
    X(hv_return_t, hv_vcpus_exit, (hv_vcpu_t *vcpus, uint32_t vcpu_count)) \
    X(hv_return_t, hv_vcpu_get_reg, (hv_vcpu_t vcpu, hv_reg_t reg, uint64_t *value)) \
    X(hv_return_t, hv_vcpu_set_reg, (hv_vcpu_t vcpu, hv_reg_t reg, uint64_t value)) \
    X(hv_return_t, hv_vcpu_get_simd_fp_reg, (hv_vcpu_t vcpu, hv_simd_fp_reg_t reg, hv_simd_fp_uchar16_t *value)) \
    X(hv_return_t, hv_vcpu_set_simd_fp_reg, (hv_vcpu_t vcpu, hv_simd_fp_reg_t reg, hv_simd_fp_uchar16_t value)) \
    X(hv_return_t, hv_vcpu_get_sys_reg, (hv_vcpu_t vcpu, hv_sys_reg_t reg, uint64_t *value)) \
    X(hv_return_t, hv_vcpu_set_sys_reg, (hv_vcpu_t vcpu, hv_sys_reg_t reg, uint64_t value)) \
    X(hv_return_t, hv_vcpu_set_pending_interrupt, (hv_vcpu_t vcpu, hv_interrupt_type_t type, bool pending)) \
    X(hv_return_t, hv_vcpu_set_trap_debug_exceptions, (hv_vcpu_t vcpu, bool value)) \
    X(hv_return_t, hv_vcpu_set_trap_debug_reg_accesses, (hv_vcpu_t vcpu, bool value)) \
    X(hv_return_t, hv_vcpu_set_vtimer_mask, (hv_vcpu_t vcpu, bool vtimer_is_masked)) \
    X(hv_return_t, hv_vcpu_set_vtimer_offset, (hv_vcpu_t vcpu, uint64_t vtimer_offset)) \
    X(hv_vcpu_config_t, hv_vcpu_config_create, (void)) \
    X(hv_return_t, hv_vcpu_config_get_feature_reg, (hv_vcpu_config_t config, hv_feature_reg_t feature_reg, uint64_t *value))

/* Functions from libSystem that the accelerator also uses */
#define HVF_SYSTEM_FUNCTIONS(X) \
    X(uint64_t, mach_absolute_time, (void)) \
    X(void, os_release, (void *object))

struct HVFDispatch {
    bool loaded;
#define HVF_MEMBER(ret, name, args) ret (*name) args;
    HVF_FUNCTIONS(HVF_MEMBER)
    HVF_SYSTEM_FUNCTIONS(HVF_MEMBER)
#undef HVF_MEMBER
};

extern struct HVFDispatch hvf_dispatch;

/* Loads the framework; false (with a message) when it is not available */
struct Error;
bool hvf_cosmo_load(struct Error **errp);

/* Calls made before hvf_cosmo_load() succeeded are a bug */
void hvf_cosmo_not_loaded(void) __attribute__((noreturn));
static inline struct HVFDispatch *hvf_fns(void)
{
    if (!hvf_dispatch.loaded) {
        hvf_cosmo_not_loaded();
    }
    return &hvf_dispatch;
}

#ifndef HVF_NO_REDIRECT
#define hv_vm_create (hvf_fns()->hv_vm_create)
#define hv_vm_map (hvf_fns()->hv_vm_map)
#define hv_vm_unmap (hvf_fns()->hv_vm_unmap)
#define hv_vm_protect (hvf_fns()->hv_vm_protect)
#define hv_vm_config_create (hvf_fns()->hv_vm_config_create)
#define hv_vm_config_get_max_ipa_size (hvf_fns()->hv_vm_config_get_max_ipa_size)
#define hv_vm_config_get_default_ipa_size (hvf_fns()->hv_vm_config_get_default_ipa_size)
#define hv_vm_config_set_ipa_size (hvf_fns()->hv_vm_config_set_ipa_size)
#define hv_vcpu_create (hvf_fns()->hv_vcpu_create)
#define hv_vcpu_destroy (hvf_fns()->hv_vcpu_destroy)
#define hv_vcpu_run (hvf_fns()->hv_vcpu_run)
#define hv_vcpus_exit (hvf_fns()->hv_vcpus_exit)
#define hv_vcpu_get_reg (hvf_fns()->hv_vcpu_get_reg)
#define hv_vcpu_set_reg (hvf_fns()->hv_vcpu_set_reg)
#define hv_vcpu_get_simd_fp_reg (hvf_fns()->hv_vcpu_get_simd_fp_reg)
#define hv_vcpu_set_simd_fp_reg (hvf_fns()->hv_vcpu_set_simd_fp_reg)
#define hv_vcpu_get_sys_reg (hvf_fns()->hv_vcpu_get_sys_reg)
#define hv_vcpu_set_sys_reg (hvf_fns()->hv_vcpu_set_sys_reg)
#define hv_vcpu_set_pending_interrupt (hvf_fns()->hv_vcpu_set_pending_interrupt)
#define hv_vcpu_set_trap_debug_exceptions (hvf_fns()->hv_vcpu_set_trap_debug_exceptions)
#define hv_vcpu_set_trap_debug_reg_accesses (hvf_fns()->hv_vcpu_set_trap_debug_reg_accesses)
#define hv_vcpu_set_vtimer_mask (hvf_fns()->hv_vcpu_set_vtimer_mask)
#define hv_vcpu_set_vtimer_offset (hvf_fns()->hv_vcpu_set_vtimer_offset)
#define hv_vcpu_config_create (hvf_fns()->hv_vcpu_config_create)
#define hv_vcpu_config_get_feature_reg (hvf_fns()->hv_vcpu_config_get_feature_reg)
#define mach_absolute_time (hvf_fns()->mach_absolute_time)
#define os_release (hvf_fns()->os_release)
#endif /* HVF_NO_REDIRECT */

#endif /* COSMO_HYPERVISOR_H */
