// Win64 compiler portability; native address guards and behavior retained.
#ifdef _MSC_VER
#include <intrin.h>
#define PCL_MS_ABI
#define PCL_ALIGN(n) __declspec(align(n))
#else
#define PCL_MS_ABI __attribute__((ms_abi))
#define PCL_ALIGN(n) __attribute__((aligned(n)))
#endif
// Phase 15.11.52 - STOCK-FREE DETOUR-OWNED GENERAL ZERO-COPY.
//
// 15.11.47 proved that normal Creative/Magic Word loads can eliminate the
// repeated AppliedSwordParts deep copies without rewriting reconstruction
// call-site bytes. A later long-session crash still looked like delayed heap
// corruption: four large zero-copy loads completed cleanly, then UE4SS died
// during an unrelated PCL reflected-field apply loop.
//
// The remaining ownership difference was our immediate raw-free of the fresh
// destination allocation inside the copy hook. 15.11.52 preserves the stock
// allocator/free lifetime exactly:
//   1) let the stock allocator create the destination buffer,
//   2) keep that unused allocation alive,
//   3) redirect only the temporary TArray header to the source array,
//   4) skip the deep copy,
//   5) at the matching temporary destructor, suppress destruction of the
//      borrowed source elements and restore the original allocation pointer,
//   6) let the caller's own immediately-following stock Free(Data) release the
//      allocation at the normal site and normal time.
//
// No direct raw-free is performed by the general zero-copy path. The legacy
// exact-byte-guarded PCL direct-import alias is unchanged.
//
// 15.11.52 also removes the temporary 15.11.49 actor_make helper detours from
// the installed profiler. They already identified 0x45F8080 as the dominant
// actor_make helper and are no longer needed while stability is being proven.
// Base actor_make/spawn/link profiling, deferred refresh, and zero-copy
// telemetry remain.
//
// Current executable guard: SizeOfImage 0x090A0000 (SHA-256
// aa1bac3999efc47f999199c10db0bfe973014f5bbd822ed2d8c36232e4ed8ca0).

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef long long i64;
typedef long NTSTATUS;
typedef unsigned long ULONG;
typedef unsigned long long SIZE_T;

template <typename T> static inline T rd(u64 p) { return *(volatile T*)(p); }
template <typename T> static inline void wr(u64 p, T v) { *(volatile T*)(p) = v; }

static inline u64 get_teb() {
    u64 v;
#ifdef _MSC_VER
    v=__readgsqword(0x30);
#else
    __asm__("movq %%gs:0x30, %0" : "=r"(v));
#endif
    return v;
}

static inline u64 get_peb() {
    u64 v;
#ifdef _MSC_VER
    v=__readgsqword(0x60);
#else
    __asm__("movq %%gs:0x60, %0" : "=r"(v));
#endif
    return v;
}

static u64 get_main_module_base() {
    const u64 peb = get_peb();
    if (!peb) return 0;
    const u64 ldr = rd<u64>(peb + 0x18);
    if (!ldr) return 0;
    const u64 head = ldr + 0x20;
    const u64 first_link = rd<u64>(head);
    if (!first_link || first_link == head) return 0;
    return rd<u64>(first_link + 0x20);
}

static bool ascii_eq(const char* a, const char* b) {
    if (!a || !b) return false;
    while (*a && *b) { if (*a != *b) return false; ++a; ++b; }
    return *a == 0 && *b == 0;
}

static bool unicode_basename_eq(u64 us_addr, const char* ascii_lower) {
    // UNICODE_STRING: USHORT Length, USHORT MaximumLength, PWSTR Buffer
    const u16 len_bytes = rd<u16>(us_addr + 0x0);
    const u64 buf = rd<u64>(us_addr + 0x8);
    if (!buf) return false;
    u32 n = (u32)(len_bytes / 2);
    u32 i = 0;
    for (; ascii_lower[i] != 0; ++i) {
        if (i >= n) return false;
        u16 wc = rd<u16>(buf + (u64)i * 2ull);
        char c = (char)(wc & 0xFF);
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a');
        if (c != ascii_lower[i]) return false;
    }
    return i == n;
}

static u64 find_loaded_module(const char* basename_lower) {
    const u64 peb = get_peb();
    if (!peb) return 0;
    const u64 ldr = rd<u64>(peb + 0x18);
    if (!ldr) return 0;
    const u64 head = ldr + 0x20;
    u64 link = rd<u64>(head);
    for (int guard = 0; link && link != head && guard < 128; ++guard) {
        // link points to entry + 0x10 (InMemoryOrderLinks)
        const u64 base = rd<u64>(link + 0x20);
        if (base && unicode_basename_eq(link + 0x48, basename_lower)) return base;
        link = rd<u64>(link + 0x0);
    }
    return 0;
}

static u64 export_by_name(u64 module, const char* wanted) {
    if (!module || rd<u16>(module) != 0x5A4D) return 0;
    const u32 peoff = rd<u32>(module + 0x3C);
    const u64 nt = module + peoff;
    if (rd<u32>(nt) != 0x00004550u) return 0;
    const u64 opt = nt + 0x18;
    // PE32+ export directory data directory is OptionalHeader + 0x70.
    const u32 exp_rva = rd<u32>(opt + 0x70);
    const u32 exp_size = rd<u32>(opt + 0x74);
    if (!exp_rva || !exp_size) return 0;
    const u64 exp = module + exp_rva;
    const u32 n_names = rd<u32>(exp + 0x18);
    const u32 funcs_rva = rd<u32>(exp + 0x1C);
    const u32 names_rva = rd<u32>(exp + 0x20);
    const u32 ords_rva = rd<u32>(exp + 0x24);
    for (u32 i = 0; i < n_names; ++i) {
        const u32 name_rva = rd<u32>(module + names_rva + (u64)i * 4ull);
        const char* name = (const char*)(module + name_rva);
        if (ascii_eq(name, wanted)) {
            const u16 ord = rd<u16>(module + ords_rva + (u64)i * 2ull);
            const u32 fn_rva = rd<u32>(module + funcs_rva + (u64)ord * 4ull);
            // Do not accept forwarded exports.
            if (fn_rva >= exp_rva && fn_rva < exp_rva + exp_size) return 0;
            return module + fn_rva;
        }
    }
    return 0;
}

// ntdll routines, resolved without imports.
typedef NTSTATUS (PCL_MS_ABI *NtProtectVirtualMemoryFn)(void*, void**, SIZE_T*, ULONG, ULONG*);
typedef NTSTATUS (PCL_MS_ABI *NtFlushInstructionCacheFn)(void*, void*, ULONG);
typedef NTSTATUS (PCL_MS_ABI *NtQueryPerformanceCounterFn)(i64*, i64*);

static NtProtectVirtualMemoryFn g_protect = 0;
static NtFlushInstructionCacheFn g_flush = 0;
static NtQueryPerformanceCounterFn g_qpc = 0;
static i64 g_qpf = 0;

// Bladesong/UE raw deallocator used by the stock TArray cleanup immediately
// after FAppliedSwordPart element destruction. We only call it on the fresh,
// still-uninitialized destination buffer returned by the stock clone allocator.
typedef void (PCL_MS_ABI *RawFreeFn)(void*);
static RawFreeFn g_raw_free = 0;

// Borrowed-array patch state. 15.11.43 allows the native EnterForgeMode hook
// to activate these patches just-in-time for any >=512-part creation load. The
// explicit PCL direct path may still request the same patch through Lua.
static volatile i64 g_alias_requested = 0;
static volatile i64 g_alias_active = 0;
static volatile i64 g_alias_patch_status = 0;
static volatile i64 g_alias_enable_count = 0;
static volatile u64 g_alias_patch_mask = 0;

static u8 g_alias_saved_top_root[62];
static u8 g_alias_saved_top_extra[65];
static u8 g_alias_saved_node_clone[62];
static u8 g_alias_saved_slot_clone[62];
static u8 g_alias_saved_free_make[66];
static u8 g_alias_saved_free_recurse[62];
static u8 g_alias_saved_node_cleanup[26];
static u8 g_alias_saved_free_cleanup[31];
static u8 g_alias_saved_walker_cleanup[27];

static const u8 k_top_root_expected[62] = {0x48,0x8D,0x44,0x24,0x4C,0x48,0x89,0x44,0x24,0x30,0x89,0x5C,0x24,0x28,0x48,0x8D,0x44,0x24,0x40,0x48,0x89,0x44,0x24,0x20,0x45,0x33,0xC9,0x44,0x8B,0xC3,0xBA,0x10,0x00,0x00,0x00,0xB9,0x20,0x01,0x00,0x00,0xE8,0x6D,0x5A,0xB1,0xFC,0x44,0x8B,0xC3,0x49,0x8B,0xD4,0x48,0x8B,0x4C,0x24,0x40,0xE8,0x1D,0x46,0xF8,0xFF,0x90};
static const u8 k_top_extra_expected[65] = {0x48,0x8D,0x44,0x24,0x4C,0x48,0x89,0x44,0x24,0x30,0x44,0x89,0x74,0x24,0x28,0x48,0x8D,0x44,0x24,0x40,0x48,0x89,0x44,0x24,0x20,0x45,0x33,0xC9,0x45,0x8B,0xC6,0xBA,0x10,0x00,0x00,0x00,0xB9,0x20,0x01,0x00,0x00,0xE8,0x75,0x59,0xB1,0xFC,0x45,0x8B,0xC6,0x49,0x8B,0xD5,0x48,0x8B,0x4C,0x24,0x40,0xE8,0x25,0x45,0xF8,0xFF,0x45,0x33,0xED};
static const u8 k_node_clone_expected[62] = {0x48,0x8D,0x44,0x24,0x54,0x48,0x89,0x44,0x24,0x30,0x89,0x7C,0x24,0x28,0x48,0x8D,0x44,0x24,0x48,0x48,0x89,0x44,0x24,0x20,0x45,0x33,0xC9,0x44,0x8B,0xC7,0xBA,0x10,0x00,0x00,0x00,0xB9,0x20,0x01,0x00,0x00,0xE8,0x93,0x9D,0xB3,0xFC,0x44,0x8B,0xC7,0x48,0x8B,0xD5,0x48,0x8B,0x4C,0x24,0x48,0xE8,0x43,0x89,0xFA,0xFF,0x90};
static const u8 k_slot_clone_expected[62] = {0x48,0x8D,0x44,0x24,0x4C,0x48,0x89,0x44,0x24,0x30,0x89,0x5C,0x24,0x28,0x48,0x8D,0x44,0x24,0x40,0x48,0x89,0x44,0x24,0x20,0x45,0x33,0xC9,0x44,0x8B,0xC3,0xBA,0x10,0x00,0x00,0x00,0xB9,0x20,0x01,0x00,0x00,0xE8,0x4A,0x9C,0xB3,0xFC,0x44,0x8B,0xC3,0x49,0x8B,0xD5,0x48,0x8B,0x4C,0x24,0x40,0xE8,0xFA,0x87,0xFA,0xFF,0x90};
static const u8 k_free_make_expected[66] = {0x48,0x8D,0x44,0x24,0x4C,0x48,0x89,0x44,0x24,0x30,0x89,0x5C,0x24,0x28,0x48,0x8D,0x44,0x24,0x40,0x48,0x89,0x44,0x24,0x20,0x45,0x33,0xC9,0x44,0x8B,0xC3,0xBA,0x10,0x00,0x00,0x00,0xB9,0x20,0x01,0x00,0x00,0xE8,0x60,0x9B,0xB3,0xFC,0x44,0x8B,0xC3,0x49,0x8B,0xD5,0x48,0x8B,0x4C,0x24,0x40,0xE8,0x10,0x87,0xFA,0xFF,0x48,0x8B,0x54,0x24,0x40};
static const u8 k_free_recurse_expected[62] = {0x48,0x8D,0x44,0x24,0x74,0x48,0x89,0x44,0x24,0x30,0x89,0x5C,0x24,0x28,0x48,0x8D,0x44,0x24,0x68,0x48,0x89,0x44,0x24,0x20,0x45,0x33,0xC9,0x44,0x8B,0xC3,0xBA,0x10,0x00,0x00,0x00,0xB9,0x20,0x01,0x00,0x00,0xE8,0x7A,0x9A,0xB3,0xFC,0x44,0x8B,0xC3,0x49,0x8B,0xD4,0x48,0x8B,0x4C,0x24,0x68,0xE8,0x2A,0x86,0xFA,0xFF,0x90};

static const u8 k_node_cleanup_expected[26] = {0x8B,0x53,0x08,0x48,0x8B,0x0B,0xE8,0x73,0x83,0xF9,0xFF,0x90,0x48,0x8B,0x0B,0x48,0x85,0xC9,0x74,0x06,0xE8,0x65,0xC4,0xBB,0xFC,0x90};
static const u8 k_free_cleanup_expected[31] = {0x8B,0x54,0x24,0x48,0x48,0x8B,0x4C,0x24,0x40,0xE8,0x50,0x80,0xF9,0xFF,0x90,0x48,0x8B,0x4C,0x24,0x40,0x48,0x85,0xC9,0x74,0x06,0xE8,0x40,0xC1,0xBB,0xFC,0x90};
static const u8 k_walker_cleanup_expected[27] = {0x41,0x8B,0x56,0x08,0x49,0x8B,0x0E,0xE8,0x1B,0x80,0xF9,0xFF,0x90,0x49,0x8B,0x0E,0x48,0x85,0xC9,0x74,0x06,0xE8,0x0D,0xC1,0xBB,0xFC,0x90};

static const u8 k_top_root_patch[] = {0x4C,0x89,0x64,0x24,0x40,0x89,0x5C,0x24,0x48,0x8B,0x85,0xD4,0x00,0x00,0x00,0x89,0x44,0x24,0x4C};
static const u8 k_top_extra_patch[] = {0x4C,0x89,0x6C,0x24,0x40,0x44,0x89,0x74,0x24,0x48,0x8B,0x85,0xD4,0x00,0x00,0x00,0x89,0x44,0x24,0x4C,0x45,0x33,0xED};
static const u8 k_node_clone_patch[] = {0x48,0x8B,0x03,0x48,0x89,0x44,0x24,0x48,0x8B,0x43,0x08,0x89,0x44,0x24,0x50,0x8B,0x43,0x0C,0x89,0x44,0x24,0x54};
static const u8 k_slot_clone_patch[] = {0x49,0x8B,0x06,0x48,0x89,0x44,0x24,0x40,0x41,0x8B,0x46,0x08,0x89,0x44,0x24,0x48,0x41,0x8B,0x46,0x0C,0x89,0x44,0x24,0x4C};
static const u8 k_free_make_patch[] = {0x49,0x8B,0x06,0x48,0x89,0x44,0x24,0x40,0x41,0x8B,0x46,0x08,0x89,0x44,0x24,0x48,0x41,0x8B,0x46,0x0C,0x89,0x44,0x24,0x4C,0x48,0x8B,0x54,0x24,0x40};
static const u8 k_free_recurse_patch[] = {0x48,0x8B,0x44,0x24,0x40,0x48,0x89,0x44,0x24,0x68,0x8B,0x44,0x24,0x48,0x89,0x44,0x24,0x70,0x8B,0x44,0x24,0x4C,0x89,0x44,0x24,0x74};

static bool resolve_ntdll() {
    const u64 ntdll = find_loaded_module("ntdll.dll");
    if (!ntdll) return false;
    g_protect = (NtProtectVirtualMemoryFn)export_by_name(ntdll, "NtProtectVirtualMemory");
    g_flush = (NtFlushInstructionCacheFn)export_by_name(ntdll, "NtFlushInstructionCache");
    g_qpc = (NtQueryPerformanceCounterFn)export_by_name(ntdll, "NtQueryPerformanceCounter");
    if (!g_protect || !g_flush || !g_qpc) return false;
    i64 now = 0, freq = 0;
    if (g_qpc(&now, &freq) < 0 || freq <= 0) return false;
    g_qpf = freq;
    return true;
}

static inline i64 qpc_now() {
    i64 v = 0;
    if (g_qpc) g_qpc(&v, 0);
    return v;
}

static i64 qpc_to_us(i64 ticks) {
    if (ticks <= 0 || g_qpf <= 0) return 0;
    // Avoid overflow for the sub-minute timings we care about.
    return (ticks * 1000000ll) / g_qpf;
}

static bool protect_rw_x(void* p, SIZE_T n, ULONG* oldp) {
    if (!g_protect || !p || !n) return false;
    void* base = p;
    SIZE_T size = n;
    ULONG oldv = 0;
    NTSTATUS st = g_protect((void*)(i64)-1, &base, &size, 0x40u /* PAGE_EXECUTE_READWRITE */, &oldv);
    if (st < 0) return false;
    if (oldp) *oldp = oldv;
    return true;
}

static void restore_protect(void* p, SIZE_T n, ULONG oldp) {
    if (!g_protect || !p || !n) return;
    void* base = p;
    SIZE_T size = n;
    ULONG ignored = 0;
    g_protect((void*)(i64)-1, &base, &size, oldp, &ignored);
}

static void flush_code(void* p, ULONG n) {
    if (g_flush) g_flush((void*)(i64)-1, p, n);
}

static void emit_abs_jump(u8* out, u64 dst) {
    // Register-preserving absolute jump:
    //   jmp qword ptr [rip+0]
    //   dq dst
    // Unlike mov rax,imm64/jmp rax, this does NOT clobber RAX.
    out[0] = 0xFF; out[1] = 0x25;
    out[2] = 0x00; out[3] = 0x00; out[4] = 0x00; out[5] = 0x00;
    *(u64*)(out + 6) = dst;
}

static bool bytes_match(u64 p, const u8* sig, u32 n) {
    for (u32 i = 0; i < n; ++i) if (rd<u8>(p + i) != sig[i]) return false;
    return true;
}


static bool patch_guarded_region(u64 target, const u8* expected, u32 len,
                                 const u8* patch, u32 patch_len, u8* saved) {
    if (!target || !expected || !len || !saved || patch_len > len) return false;
    if (!bytes_match(target, expected, len)) return false;
    ULONG oldp = 0;
    if (!protect_rw_x((void*)target, len, &oldp)) return false;
    for (u32 i = 0; i < len; ++i) saved[i] = rd<u8>(target + i);
    for (u32 i = 0; i < len; ++i) wr<u8>(target + i, (i < patch_len && patch) ? patch[i] : (u8)0x90);
    flush_code((void*)target, len);
    restore_protect((void*)target, len, oldp);
    return true;
}

static bool restore_guarded_region(u64 target, const u8* saved, u32 len) {
    if (!target || !saved || !len) return false;
    ULONG oldp = 0;
    if (!protect_rw_x((void*)target, len, &oldp)) return false;
    for (u32 i = 0; i < len; ++i) wr<u8>(target + i, saved[i]);
    flush_code((void*)target, len);
    restore_protect((void*)target, len, oldp);
    return true;
}

static void restore_alias_patches() {
    u64 remaining = g_alias_patch_mask;
    if (!remaining) { g_alias_active = 0; return; }
    const u64 base = get_main_module_base();
    if (!base) {
        // Do not pretend restoration succeeded if the main module vanished.
        // Keep the mask so a later disarm can retry.
        g_alias_active = 1;
        return;
    }

#define PCL_ALIAS_RESTORE(BIT, RVA, SAVED, LEN) \
    do { \
        const u64 b = (1ull << (BIT)); \
        if ((remaining & b) && restore_guarded_region(base + (RVA), (SAVED), (LEN))) remaining &= ~b; \
    } while (0)

    // Reverse application order. Restore only regions that were actually
    // modified, making partial-failure rollback safe.
    PCL_ALIAS_RESTORE(8, 0x04597099ull, g_alias_saved_walker_cleanup, 27);
    PCL_ALIAS_RESTORE(7, 0x04597062ull, g_alias_saved_free_cleanup, 31);
    PCL_ALIAS_RESTORE(6, 0x04596D42ull, g_alias_saved_node_cleanup, 26);
    PCL_ALIAS_RESTORE(5, 0x04597009ull, g_alias_saved_free_recurse, 62);
    PCL_ALIAS_RESTORE(4, 0x04596F23ull, g_alias_saved_free_make, 66);
    PCL_ALIAS_RESTORE(3, 0x04596E39ull, g_alias_saved_slot_clone, 62);
    PCL_ALIAS_RESTORE(2, 0x04596CF0ull, g_alias_saved_node_clone, 62);
    PCL_ALIAS_RESTORE(1, 0x045BB10Dull, g_alias_saved_top_extra, 65);
    PCL_ALIAS_RESTORE(0, 0x045BB016ull, g_alias_saved_top_root, 62);

#undef PCL_ALIAS_RESTORE

    g_alias_patch_mask = remaining;
    g_alias_active = remaining ? 1 : 0;
}

static int apply_alias_patches() {
    if (g_alias_active && g_alias_patch_mask == 0x1FFull) return 1;
    const u64 base = get_main_module_base();
    if (!base) return -101;

    // Exact-byte preflight all nine sites before modifying any instruction.
    // This keeps unsupported game builds entirely stock and greatly reduces
    // the chance of entering a partial patch state.
    if (!bytes_match(base + 0x045BB016ull, k_top_root_expected, 62)) return -111;
    if (!bytes_match(base + 0x045BB10Dull, k_top_extra_expected, 65)) return -112;
    if (!bytes_match(base + 0x04596CF0ull, k_node_clone_expected, 62)) return -113;
    if (!bytes_match(base + 0x04596E39ull, k_slot_clone_expected, 62)) return -114;
    if (!bytes_match(base + 0x04596F23ull, k_free_make_expected, 66)) return -115;
    if (!bytes_match(base + 0x04597009ull, k_free_recurse_expected, 62)) return -116;
    if (!bytes_match(base + 0x04596D42ull, k_node_cleanup_expected, 26)) return -117;
    if (!bytes_match(base + 0x04597062ull, k_free_cleanup_expected, 31)) return -118;
    if (!bytes_match(base + 0x04597099ull, k_walker_cleanup_expected, 27)) return -119;

    g_alias_patch_mask = 0;

#define PCL_ALIAS_PATCH(BIT, RVA, EXPECTED, LEN, PATCH, SAVED, ERR) \
    do { \
        if (!patch_guarded_region(base + (RVA), (EXPECTED), (LEN), (PATCH), (u32)sizeof(PATCH), (SAVED))) { \
            restore_alias_patches(); \
            return (ERR); \
        } \
        g_alias_patch_mask |= (1ull << (BIT)); \
    } while (0)

    PCL_ALIAS_PATCH(0, 0x045BB016ull, k_top_root_expected, 62, k_top_root_patch, g_alias_saved_top_root, -111);
    PCL_ALIAS_PATCH(1, 0x045BB10Dull, k_top_extra_expected, 65, k_top_extra_patch, g_alias_saved_top_extra, -112);
    PCL_ALIAS_PATCH(2, 0x04596CF0ull, k_node_clone_expected, 62, k_node_clone_patch, g_alias_saved_node_clone, -113);
    PCL_ALIAS_PATCH(3, 0x04596E39ull, k_slot_clone_expected, 62, k_slot_clone_patch, g_alias_saved_slot_clone, -114);
    PCL_ALIAS_PATCH(4, 0x04596F23ull, k_free_make_expected, 66, k_free_make_patch, g_alias_saved_free_make, -115);
    PCL_ALIAS_PATCH(5, 0x04597009ull, k_free_recurse_expected, 62, k_free_recurse_patch, g_alias_saved_free_recurse, -116);

#undef PCL_ALIAS_PATCH

    if (!patch_guarded_region(base + 0x04596D42ull, k_node_cleanup_expected, 26, 0, 0, g_alias_saved_node_cleanup)) {
        restore_alias_patches(); return -117;
    }
    g_alias_patch_mask |= (1ull << 6);
    if (!patch_guarded_region(base + 0x04597062ull, k_free_cleanup_expected, 31, 0, 0, g_alias_saved_free_cleanup)) {
        restore_alias_patches(); return -118;
    }
    g_alias_patch_mask |= (1ull << 7);
    if (!patch_guarded_region(base + 0x04597099ull, k_walker_cleanup_expected, 27, 0, 0, g_alias_saved_walker_cleanup)) {
        restore_alias_patches(); return -119;
    }
    g_alias_patch_mask |= (1ull << 8);

    g_alias_active = (g_alias_patch_mask == 0x1FFull) ? 1 : 0;
    if (!g_alias_active) {
        restore_alias_patches();
        return -120;
    }
    g_alias_enable_count++;
    return 1;
}

PCL_ALIGN(64) static u8 g_enter_tramp[64];
PCL_ALIGN(64) static u8 g_seam_tramp[64];
PCL_ALIGN(64) static u8 g_child_a_tramp[64];
PCL_ALIGN(64) static u8 g_child_b_tramp[64];
PCL_ALIGN(64) static u8 g_child_c_tramp[64];
PCL_ALIGN(64) static u8 g_child_d_tramp[64];
PCL_ALIGN(64) static u8 g_child_e_tramp[64];
PCL_ALIGN(64) static u8 g_copy_tramp[64];
PCL_ALIGN(64) static u8 g_clone_alloc_tramp[64];
PCL_ALIGN(64) static u8 g_clone_destroy_tramp[64];
PCL_ALIGN(64) static u8 g_actor_make_tramp[64];
PCL_ALIGN(64) static u8 g_actor_link_tramp[64];
PCL_ALIGN(64) static u8 g_child_refresh_tramp[64];
PCL_ALIGN(64) static u8 g_link_notify_tramp[64];
PCL_ALIGN(64) static u8 g_link_map_tramp[64];
PCL_ALIGN(64) static u8 g_actor_spawn_tramp[64];
PCL_ALIGN(64) static u8 g_actor_resolve_tramp[64];
PCL_ALIGN(64) static u8 g_actor_data_tramp[64];

typedef void (PCL_MS_ABI *TwoArgFn)(void*, void*);
typedef u64 (PCL_MS_ABI *OneArgRetFn)(void*);
typedef u64 (PCL_MS_ABI *ThreeArgRetFn)(void*, void*, void*);
typedef void (PCL_MS_ABI *CopyArrayFn)(void*, void*, u32);
typedef u64 (PCL_MS_ABI *SevenArgRetFn)(u64,u64,u64,u64,u64,u64,u64);
typedef u64 (PCL_MS_ABI *TwoArgRetFn)(void*, void*);
typedef void (PCL_MS_ABI *ThreeArgByteVoidFn)(void*, u8, u8);
typedef u64 (PCL_MS_ABI *FourArgRetFn)(void*, void*, void*, void*);
typedef u64 (PCL_MS_ABI *FiveArgRetFn)(void*, void*, void*, void*, void*);
static TwoArgFn g_enter_orig = 0;
static TwoArgFn g_seam_orig = 0;
static OneArgRetFn g_child_a_orig = 0;
static ThreeArgRetFn g_child_b_orig = 0;
static ThreeArgRetFn g_child_c_orig = 0;
static OneArgRetFn g_child_d_orig = 0;
static OneArgRetFn g_child_e_orig = 0;
static CopyArrayFn g_copy_orig = 0;
static SevenArgRetFn g_clone_alloc_orig = 0;
static void (PCL_MS_ABI *g_clone_destroy_orig)(void*, u32) = 0;
static TwoArgRetFn g_actor_make_orig = 0;
static ThreeArgRetFn g_actor_link_orig = 0;
static ThreeArgByteVoidFn g_child_refresh_orig = 0;
static FourArgRetFn g_link_notify_orig = 0;
static FourArgRetFn g_link_map_orig = 0;
static FiveArgRetFn g_actor_spawn_orig = 0;
static TwoArgRetFn g_actor_resolve_orig = 0;
static ThreeArgRetFn g_actor_data_orig = 0;

// Phase 15.11.20.1 deliberately does NOT detour the asynchronous HTTP callback.
// The reflected DownloadPiece hook arms the clock. Native EnterForgeMode and the
// native reconstruction seam provide all timings needed to isolate high-piece
// rebuild cost, without relying on the callback prototype.
static volatile i64 g_arm_qpc = 0;
static volatile i64 g_enter_begin = 0, g_enter_end = 0;
static volatile i64 g_seam_begin = 0, g_seam_end = 0;
static volatile i64 g_last_piece = 0;
static volatile i64 g_enter_count = 0, g_seam_count = 0;
static volatile i64 g_armed = 0;
static volatile i64 g_installed = 0;
static volatile i64 g_in_seam = 0;

// Direct-child timings inside the native reconstruction seam.  These are
// intentionally labeled A-E until profiling tells us which stage dominates.
static volatile i64 g_child_a_ticks = 0, g_child_a_count = 0;
static volatile i64 g_child_b_ticks = 0, g_child_b_count = 0;
static volatile i64 g_child_c_ticks = 0, g_child_c_count = 0;
static volatile i64 g_child_d_ticks = 0, g_child_d_count = 0;
static volatile i64 g_child_e_ticks = 0, g_child_e_count = 0;

// Phase 15.11.22: Child D is the blade reconstruction stage. Track how much
// FAppliedSwordPart array copying occurs while that stage is active.
static volatile i64 g_in_child_d = 0;
static volatile i64 g_applied_count = 0, g_blade_count = 0;
static volatile i64 g_copy_ticks = 0, g_copy_calls = 0, g_copy_elements = 0;

// Phase 15.11.23: classify the remaining per-part cost.  The clone allocator
// is filtered to element_size=0x120 and count==AppliedSwordParts.Num so we do
// not accidentally count unrelated allocations performed while a part builds.
static volatile i64 g_clone_alloc_ticks = 0, g_clone_alloc_calls = 0;
static volatile i64 g_clone_destroy_ticks = 0, g_clone_destroy_calls = 0;
static volatile i64 g_actor_make_ticks = 0, g_actor_make_calls = 0;
static volatile i64 g_actor_link_ticks = 0, g_actor_link_calls = 0;

// Phase 15.11.27: same 15.11.25 substage profiler, rebased for the updated EXE,
// with the Child-D clone-allocation helper corrected from 0x10D1A90 to 0x10D0AB0.
// Link path: 0x3412800 pre-notify/registration helper and 0x45C97A0 map insertion helper.
// Make path: 0x39B5920 actor spawn core, 0x45ACF20 row/class resolver, and its
// nested 0x45A59A0 data-table/material data resolution helper.
static volatile i64 g_in_actor_make = 0;
static volatile i64 g_link_notify_ticks = 0, g_link_notify_calls = 0;
static volatile i64 g_link_map_ticks = 0, g_link_map_calls = 0;
static volatile i64 g_actor_spawn_ticks = 0, g_actor_spawn_calls = 0;
static volatile i64 g_actor_resolve_ticks = 0, g_actor_resolve_calls = 0;
static volatile i64 g_actor_data_ticks = 0, g_actor_data_calls = 0;

// Phase 15.11.24 behavior rebased: the expensive link path calls 0x45F3BD0 after
// every slot-child insertion. 0x45F3BD0 recursively refreshes transforms for the complete subtree below that parent, and
// 0x4603750 tail-recurses back into it for every child. For large designs this repeats the
// same subtree work thousands of times. Only while the Magic Word bulk-rebuild stage is active,
// defer those calls and perform one equivalent root refresh when Child D completes.
static volatile i64 g_current_forge = 0;
static volatile i64 g_defer_refresh_active = 0;
static volatile i64 g_in_actor_link = 0;
static volatile i64 g_deferred_refresh_calls = 0;
static volatile i64 g_final_refresh_ticks = 0;
static volatile i64 g_final_refresh_calls = 0;
static volatile i64 g_final_refresh_root = 0;
static const i64 PCL_MW_DEFER_THRESHOLD = 512;

// Phase 15.11.45 general-load telemetry. These are deliberately appended to
// pcl_mw_prof_read so all historical field indices remain stable. A sequence is
// emitted for every >=512-part EnterForgeMode load, whether it was already armed
// by Magic Word DownloadPiece or auto-armed here for a normal Creative-menu load.
static volatile i64 g_general_load_seq = 0;
static volatile i64 g_general_last_pre_applied = 0;
static volatile i64 g_general_last_source_mode = 0;
static volatile i64 g_general_last_alias_status = 0;
static volatile i64 g_general_last_alias_used = 0;
static volatile i64 g_general_last_restore_ok = 1;
static volatile i64 g_general_fail_closed = 0;

// 15.11.57 general-load zero-copy lifetime fix.
//
// The 15.11.47/15.11.52 experiments aliased every recursive temporary directly
// to Piece.AppliedSwordParts. All synchronous destructor/free bookkeeping was
// clean, but later loads could still crash. That means "clean temporary lifetime"
// was not enough: some reconstructed state can outlive the seam and retain a
// pointer into the array used by the walker. On a normal Creative/Magic Word
// load the source Piece may later be replaced/destroyed, making a pure borrowed
// source pointer unsafe even though every temporary itself was cleaned up.
//
// 15.11.57 therefore creates ONE stock deep-copy backing per large general load.
// The first clone remains fully stock and becomes a persistent backing buffer;
// every subsequent recursive clone aliases that stable backing. The backing's
// final destructor/free is suppressed so any post-seam retained element pointer
// stays valid. This changes 5,975 deep copies into 1 deep copy + 5,974 aliases on
// the known 2,988-part test while preserving stable backing storage.
//
// Backings are intentionally retained for the session rather than guessed-free.
// The list is capped; once full, general loads fail open to the stock deep-copy
// path instead of risking a use-after-free. PCL direct imports keep their proven
// temporary-host + legacy guarded alias path and do not consume backing slots.
struct HookAliasRecord {
    u64 header_data_ptr_addr; // address of the caller's TArray.Data field
    u64 borrowed_data;        // persistent backing AppliedSwordParts data pointer
    u64 allocated_data;       // stock destination allocation kept until stock free
    u32 count;
    u32 reserved;
};
struct RetainedBackingRecord {
    u64 data;
    u32 count;
    u32 reserved;
};
static const u32 HOOK_ALIAS_MAX_DEPTH = 8192u;
static const u32 HOOK_BACKING_MAX_RETAINED = 64u;
static HookAliasRecord g_hook_alias_stack[HOOK_ALIAS_MAX_DEPTH];
static RetainedBackingRecord g_hook_retained_backings[HOOK_BACKING_MAX_RETAINED];
static volatile u32 g_hook_retained_backing_count = 0;
static volatile u32 g_hook_alias_depth = 0;
static volatile u32 g_hook_alias_peak = 0;
static volatile i64 g_hook_alias_enabled = 0;
static volatile i64 g_hook_alias_zero_copy_calls = 0;
static volatile i64 g_hook_alias_zero_copy_elements = 0;
static volatile i64 g_hook_alias_destroy_suppressed = 0;
static volatile i64 g_hook_alias_guard_misses = 0;
static volatile i64 g_hook_alias_fallback_copies = 0;
static volatile u64 g_hook_alias_source_data = 0;
static volatile u64 g_hook_alias_owner_teb = 0;
static volatile u64 g_hook_backing_data = 0;
static volatile u64 g_hook_backing_header_data_ptr_addr = 0;
static volatile u32 g_hook_backing_count = 0;
static volatile i64 g_hook_backing_ready = 0;
static volatile i64 g_hook_backing_retained = 0;
static volatile i64 g_hook_backing_stock_copies = 0;

// The allocator call occurs immediately before the corresponding copy call.
// Capture the stack-local Data-field address and fresh allocation here, then
// consume this pending record in pcl_mw_copy_hook.
static volatile u64 g_hook_pending_header_data_ptr_addr = 0;
static volatile u64 g_hook_pending_alloc_data = 0;
static volatile u32 g_hook_pending_count = 0;
static volatile i64 g_hook_pending_valid = 0;

static void reset_hook_alias_state() {
    g_hook_alias_depth = 0;
    g_hook_alias_peak = 0;
    g_hook_alias_enabled = 0;
    g_hook_alias_zero_copy_calls = 0;
    g_hook_alias_zero_copy_elements = 0;
    g_hook_alias_destroy_suppressed = 0;
    g_hook_alias_guard_misses = 0;
    g_hook_alias_fallback_copies = 0;
    g_hook_alias_source_data = 0;
    g_hook_alias_owner_teb = 0;
    g_hook_backing_data = 0;
    g_hook_backing_header_data_ptr_addr = 0;
    g_hook_backing_count = 0;
    g_hook_backing_ready = 0;
    g_hook_backing_retained = 0;
    g_hook_backing_stock_copies = 0;
    g_hook_pending_header_data_ptr_addr = 0;
    g_hook_pending_alloc_data = 0;
    g_hook_pending_count = 0;
    g_hook_pending_valid = 0;
}

static bool hook_alias_target() {
    return g_hook_alias_enabled != 0 && g_armed != 0 && g_in_child_d > 0 &&
           g_applied_count >= PCL_MW_DEFER_THRESHOLD &&
           g_hook_alias_owner_teb != 0 && get_teb() == g_hook_alias_owner_teb;
}

static void reset_profile_counters() {
    g_enter_begin = g_enter_end = 0;
    g_seam_begin = g_seam_end = 0;
    g_last_piece = 0;
    g_enter_count = g_seam_count = 0;
    g_in_seam = 0;
    g_child_a_ticks = g_child_b_ticks = g_child_c_ticks = g_child_d_ticks = g_child_e_ticks = 0;
    g_child_a_count = g_child_b_count = g_child_c_count = g_child_d_count = g_child_e_count = 0;
    g_in_child_d = 0;
    g_applied_count = g_blade_count = 0;
    g_copy_ticks = g_copy_calls = g_copy_elements = 0;
    g_clone_alloc_ticks = g_clone_alloc_calls = 0;
    g_clone_destroy_ticks = g_clone_destroy_calls = 0;
    g_actor_make_ticks = g_actor_make_calls = 0;
    g_actor_link_ticks = g_actor_link_calls = 0;
    g_in_actor_make = 0;
    g_link_notify_ticks = g_link_notify_calls = 0;
    g_link_map_ticks = g_link_map_calls = 0;
    g_actor_spawn_ticks = g_actor_spawn_calls = 0;
    g_actor_resolve_ticks = g_actor_resolve_calls = 0;
    g_actor_data_ticks = g_actor_data_calls = 0;
    g_current_forge = 0;
    g_defer_refresh_active = 0;
    g_in_actor_link = 0;
    g_deferred_refresh_calls = 0;
    g_final_refresh_ticks = 0;
    g_final_refresh_calls = 0;
    g_final_refresh_root = 0;
    g_alias_patch_status = 0;
    g_general_last_pre_applied = 0;
    g_general_last_source_mode = 0;
    g_general_last_alias_status = 0;
    g_general_last_alias_used = 0;
    g_general_last_restore_ok = 1;
    reset_hook_alias_state();
}

extern "C" void PCL_MS_ABI pcl_mw_enter_hook(void* gm, void* piece) {
    const u64 piece_addr = (u64)piece;
    const i64 pre_applied = piece_addr ? (i64)rd<u32>(piece_addr + 0xD0) : 0;
    bool auto_armed_here = false;

    // Normal Creative-menu loads arrive here without the reflected DownloadPiece
    // prehook. Auto-arm only for large creations so small/load-unrelated Forge
    // entries keep essentially stock overhead. Magic Word is already armed by
    // DownloadPiece. 15.11.57 gives general loads one persistent stock backing
    // copy, then aliases only the recursive temporaries to that backing.
    if (!g_armed && pre_applied >= PCL_MW_DEFER_THRESHOLD) {
        // A normal Creative-menu load must never inherit an unfinished PCL alias
        // request. Restore stock walker bytes before auto-arming the general path.
        g_alias_requested = 0;
        restore_alias_patches();
        reset_profile_counters();
        g_arm_qpc = qpc_now();
        g_armed = 1;
        auto_armed_here = true;
    }

    const bool armed = g_armed != 0;
    if (armed && pre_applied >= PCL_MW_DEFER_THRESHOLD) {
        g_general_load_seq++;
        g_general_last_pre_applied = pre_applied;
        g_general_last_source_mode = auto_armed_here ? 1 : 2;

        // 15.11.45: EnterForgeMode only arms/profiles the large load. General
        // Creative/Magic Word loads retain stock AppliedSwordParts ownership.
        // Borrowed-array recursion is reserved for explicit PCL direct imports.
        g_enter_begin = qpc_now();
        g_enter_count++;
        g_last_piece = (i64)piece_addr;
    } else if (armed) {
        g_enter_begin = qpc_now();
        g_enter_count++;
        g_last_piece = (i64)piece_addr;
    }

    g_enter_orig(gm,piece);

    if (armed) g_enter_end = qpc_now();

    // Creative-menu auto-arm is scoped exactly to this synchronous EnterForgeMode
    // call. Magic Word remains armed after return so the existing Lua poll can
    // report timings and then disarm normally.
    if (auto_armed_here) g_armed = 0;
}

extern "C" void PCL_MS_ABI pcl_mw_seam_hook(void* forge, void* piece) {
    const u64 piece_addr = (u64)piece;
    const i64 pre_applied = piece_addr ? (i64)rd<u32>(piece_addr + 0xD0) : 0;
    bool auto_armed_here = false;
    bool alias_owned_here = false;
    bool hook_alias_owned_here = false;

    // Fallback coverage for any reconstruction caller that bypasses
    // EnterForgeMode entirely. This makes the optimization seam-wide rather
    // than dependent on a specific UI/download entry point.
    if (!g_armed && pre_applied >= PCL_MW_DEFER_THRESHOLD) {
        reset_profile_counters();
        g_arm_qpc = qpc_now();
        g_armed = 1;
        auto_armed_here = true;
        g_general_load_seq++;
        g_general_last_pre_applied = pre_applied;
        g_general_last_source_mode = 3; // auto_seam
    } else if (g_armed && pre_applied >= PCL_MW_DEFER_THRESHOLD && g_enter_count == 0) {
        // An externally armed direct seam (including the PCL direct path) did
        // not pass EnterForgeMode. Record it without creating a duplicate event
        // for normal EnterForgeMode -> seam loads.
        g_general_load_seq++;
        g_general_last_pre_applied = pre_applied;
        g_general_last_source_mode = 4; // prearmed_seam
    }

    const bool armed = g_armed != 0;

    // Explicit PCL direct imports keep the already-proven exact-byte call-site
    // alias in this version. All normal creation loads use the new detour-owned
    // alias below and therefore never rewrite these nine game-code regions.
    if (armed && g_alias_requested && g_general_last_source_mode == 4 &&
        pre_applied >= PCL_MW_DEFER_THRESHOLD && !g_alias_active) {
        const int st = apply_alias_patches();
        g_alias_patch_status = st;
        g_general_last_alias_status = st;
        if (st == 1) {
            alias_owned_here = true;
            g_general_last_alias_used = 1;
        } else if (g_alias_patch_mask != 0) {
            g_general_fail_closed++;
            if (auto_armed_here) g_armed = 0;
            return;
        }
    } else if (armed && g_alias_requested && g_general_last_source_mode == 4 &&
               pre_applied >= PCL_MW_DEFER_THRESHOLD && g_alias_active) {
        g_general_last_alias_status = 1;
        g_general_last_alias_used = 1;
    } else if (armed && pre_applied >= PCL_MW_DEFER_THRESHOLD) {
        // 15.11.57 persistent-backing general zero-copy. Do not borrow directly
        // from Piece.AppliedSwordParts. The first observed full-array clone is
        // kept as one stock deep-copy backing; later clones alias that buffer.
        reset_hook_alias_state();
        if (g_hook_retained_backing_count < HOOK_BACKING_MAX_RETAINED) {
            g_hook_alias_enabled = 1;
            g_hook_alias_owner_teb = get_teb();
            g_hook_alias_source_data = piece_addr ? rd<u64>(piece_addr + 0xC8) : 0;
            hook_alias_owned_here = true;
            g_general_last_alias_status = g_hook_alias_source_data ? 2 : -201;
            g_general_last_alias_used = 0;
            g_general_last_restore_ok = 1;
            if (!g_hook_alias_source_data) {
                g_hook_alias_enabled = 0;
                g_hook_alias_guard_misses++;
            }
        } else {
            // Retained-lifetime capacity exhausted: fail open to the exact stock
            // path rather than freeing a backing whose references may still live.
            g_hook_alias_enabled = 0;
            g_general_last_alias_status = -202;
            g_general_last_alias_used = 0;
            g_general_last_restore_ok = 1;
        }
    }

    if (armed) {
        g_seam_begin = qpc_now();
        g_seam_count++;
        g_last_piece = (i64)piece_addr;
        g_in_seam++;
    }
    g_seam_orig(forge,piece);
    if (armed) {
        g_in_seam--;
        g_seam_end = qpc_now();
    }

    if (hook_alias_owned_here) {
        // All short-lived aliases must be consumed, and the one stock backing
        // must have reached its cleanup site and been retained, before seam exit.
        const bool clean = (g_hook_alias_depth == 0 && g_hook_pending_valid == 0 &&
                            g_hook_backing_ready != 0 && g_hook_backing_retained != 0);
        g_general_last_alias_used = (g_hook_alias_zero_copy_calls > 0) ? 1 : 0;
        g_general_last_restore_ok = clean ? 1 : 0;
        if (!clean) {
            g_hook_alias_guard_misses++;
            g_general_fail_closed++;
        }
        g_hook_alias_enabled = 0;
        g_hook_pending_valid = 0;
        g_hook_alias_depth = 0;
        g_hook_backing_header_data_ptr_addr = 0;
    }

    if (alias_owned_here) {
        restore_alias_patches();
        if (g_alias_patch_mask != 0) restore_alias_patches();
        g_general_last_restore_ok = (g_alias_patch_mask == 0) ? 1 : 0;
        if (g_alias_patch_mask != 0) g_general_fail_closed++;
    }
    if (auto_armed_here) g_armed = 0;
}

static inline bool profile_child() { return g_armed != 0 && g_in_seam > 0; }

extern "C" u64 PCL_MS_ABI pcl_mw_child_a_hook(void* a1) {
    const bool p = profile_child(); i64 t0 = p ? qpc_now() : 0;
    u64 r = g_child_a_orig(a1);
    if (p) { g_child_a_ticks += qpc_now() - t0; g_child_a_count++; }
    return r;
}
extern "C" u64 PCL_MS_ABI pcl_mw_child_b_hook(void* a1, void* a2, void* a3) {
    const bool p = profile_child(); i64 t0 = p ? qpc_now() : 0;
    u64 r = g_child_b_orig(a1,a2,a3);
    if (p) { g_child_b_ticks += qpc_now() - t0; g_child_b_count++; }
    return r;
}
extern "C" u64 PCL_MS_ABI pcl_mw_child_c_hook(void* a1, void* a2, void* a3) {
    const bool p = profile_child(); i64 t0 = p ? qpc_now() : 0;
    u64 r = g_child_c_orig(a1,a2,a3);
    if (p) { g_child_c_ticks += qpc_now() - t0; g_child_c_count++; }
    return r;
}
extern "C" u64 PCL_MS_ABI pcl_mw_child_d_hook(void* a1) {
    const bool p = profile_child(); i64 t0 = p ? qpc_now() : 0;
    if (p) {
        const u64 forge = (u64)a1;
        const u64 piece = forge ? rd<u64>(forge + 0x3D8) : 0;
        g_current_forge = (i64)forge;
        if (piece) {
            g_blade_count = (i64)rd<u32>(piece + 0xC0);
            g_applied_count = (i64)rd<u32>(piece + 0xD0);
        }
        g_defer_refresh_active = (g_applied_count >= PCL_MW_DEFER_THRESHOLD) ? 1 : 0;
        g_in_child_d++;
    }

    u64 r = g_child_d_orig(a1);

    if (p) {
        if (g_defer_refresh_active && g_deferred_refresh_calls > 0 && g_child_refresh_orig) {
            const u64 forge = (u64)a1;
            const u64 root = forge ? rd<u64>(forge + 0x320) : 0;
            g_final_refresh_root = (i64)root;
            if (root) {
                const i64 rt0 = qpc_now();
                g_child_refresh_orig((void*)root, (u8)1, (u8)1);
                g_final_refresh_ticks += qpc_now() - rt0;
                g_final_refresh_calls++;
            }
        }
        g_in_child_d--;
        g_defer_refresh_active = 0;
        g_current_forge = 0;
        g_child_d_ticks += qpc_now() - t0; g_child_d_count++;
    }
    return r;
}

extern "C" void PCL_MS_ABI pcl_mw_copy_hook(void* dst, void* src, u32 count) {
    const bool p = (g_armed != 0 && g_in_child_d > 0);

    if (hook_alias_target() && (i64)count == g_applied_count &&
        g_hook_pending_valid && g_hook_pending_alloc_data == (u64)dst &&
        g_hook_pending_count == count && g_hook_pending_header_data_ptr_addr && src) {
        const u64 header_addr = g_hook_pending_header_data_ptr_addr;
        const u64 allocated = g_hook_pending_alloc_data;

        if (!g_hook_backing_ready) {
            // The first full-array clone is intentionally stock. This is the
            // stable backing that may safely outlive the source Piece and seam.
            const i64 t0 = p ? qpc_now() : 0;
            g_copy_orig(dst, src, count);
            if (p) {
                g_copy_ticks += qpc_now() - t0;
                g_copy_calls++;
                g_copy_elements += (i64)count;
            }
            g_hook_backing_data = (u64)dst;
            g_hook_backing_header_data_ptr_addr = header_addr;
            g_hook_backing_count = count;
            g_hook_backing_ready = 1;
            g_hook_backing_stock_copies++;
            g_hook_pending_valid = 0;
            g_hook_pending_header_data_ptr_addr = 0;
            g_hook_pending_alloc_data = 0;
            g_hook_pending_count = 0;
            return;
        }

        if (g_hook_backing_data && g_hook_backing_count == count &&
            g_hook_alias_depth < HOOK_ALIAS_MAX_DEPTH) {
            // All remaining recursive temporaries borrow the stable backing,
            // never the original Piece buffer. Keep each temporary's own stock
            // allocation until its normal cleanup so allocator timing/ownership
            // remains unchanged apart from the skipped deep copy.
            wr<u64>(header_addr, g_hook_backing_data);

            const u32 depth = g_hook_alias_depth;
            g_hook_alias_stack[depth].header_data_ptr_addr = header_addr;
            g_hook_alias_stack[depth].borrowed_data = g_hook_backing_data;
            g_hook_alias_stack[depth].allocated_data = allocated;
            g_hook_alias_stack[depth].count = count;
            g_hook_alias_stack[depth].reserved = 0;
            g_hook_alias_depth = depth + 1;
            if (g_hook_alias_depth > g_hook_alias_peak) g_hook_alias_peak = g_hook_alias_depth;

            g_hook_alias_zero_copy_calls++;
            g_hook_alias_zero_copy_elements += (i64)count;
            g_hook_pending_valid = 0;
            g_hook_pending_header_data_ptr_addr = 0;
            g_hook_pending_alloc_data = 0;
            g_hook_pending_count = 0;
            return;
        }
    }

    // Any invariant miss falls back to the exact stock copy path. The fresh
    // allocation remains owned by the caller, so this fallback is lifecycle-safe.
    if (g_hook_pending_valid && p && (i64)count == g_applied_count) {
        g_hook_alias_fallback_copies++;
        g_hook_alias_guard_misses++;
        g_hook_pending_valid = 0;
        g_hook_pending_header_data_ptr_addr = 0;
        g_hook_pending_alloc_data = 0;
        g_hook_pending_count = 0;
    }

    const i64 t0 = p ? qpc_now() : 0;
    g_copy_orig(dst, src, count);
    if (p) {
        g_copy_ticks += qpc_now() - t0;
        g_copy_calls++;
        g_copy_elements += (i64)count;
    }
}

extern "C" u64 PCL_MS_ABI pcl_mw_clone_alloc_hook(
    u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6,u64 a7) {
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_applied_count > 0 &&
                    (u32)a1 == 0x120u && (i64)(u32)a3 == g_applied_count);
    const i64 t0 = p ? qpc_now() : 0;
    u64 r = g_clone_alloc_orig(a1,a2,a3,a4,a5,a6,a7);
    if (p) { g_clone_alloc_ticks += qpc_now() - t0; g_clone_alloc_calls++; }

    if (p && hook_alias_target()) {
        // a5 is the allocator's pointer to the caller's TArray.Data field on
        // Win64 for this exact call pattern (validated by the guarded EXE site).
        // The stock allocator has already written the fresh data pointer there.
        if (a5) {
            const u64 allocated = rd<u64>(a5);
            if (allocated) {
                g_hook_pending_header_data_ptr_addr = a5;
                g_hook_pending_alloc_data = allocated;
                g_hook_pending_count = (u32)a3;
                g_hook_pending_valid = 1;
            } else {
                g_hook_alias_guard_misses++;
            }
        } else {
            g_hook_alias_guard_misses++;
        }
    }
    return r;
}

extern "C" void PCL_MS_ABI pcl_mw_clone_destroy_hook(void* data, u32 count) {
    // Installed at Function+4, immediately after the original count==0 branch.
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_applied_count > 0 &&
                    (i64)count == g_applied_count);

    if (hook_alias_target() && p && g_hook_alias_depth > 0) {
        const u32 idx = g_hook_alias_depth - 1;
        HookAliasRecord rec = g_hook_alias_stack[idx];
        if (rec.borrowed_data == (u64)data && rec.count == count &&
            rec.header_data_ptr_addr && rd<u64>(rec.header_data_ptr_addr) == (u64)data) {
            // Short-lived alias: skip destruction of the persistent backing,
            // restore this temporary's unused stock allocation, then let the
            // caller's normal immediately-following Free(Data) release it.
            wr<u64>(rec.header_data_ptr_addr, rec.allocated_data);
            g_hook_alias_depth = idx;
            g_hook_alias_destroy_suppressed++;
            return;
        }

        g_hook_alias_guard_misses++;
        g_general_fail_closed++;
    }

    if (hook_alias_target() && p && g_hook_backing_ready && !g_hook_backing_retained &&
        (u64)data == g_hook_backing_data && count == g_hook_backing_count &&
        g_hook_backing_header_data_ptr_addr &&
        rd<u64>(g_hook_backing_header_data_ptr_addr) == g_hook_backing_data) {
        // This is the ONE stock deep-copy backing's own cleanup. Keep its fully
        // constructed elements alive and zero the stack-local Data pointer so
        // the caller's stock Free(Data) sees null. The backing allocation and
        // any nested element ownership now deliberately persist for the session.
        if (g_hook_retained_backing_count < HOOK_BACKING_MAX_RETAINED) {
            const u32 slot = g_hook_retained_backing_count;
            g_hook_retained_backings[slot].data = g_hook_backing_data;
            g_hook_retained_backings[slot].count = g_hook_backing_count;
            g_hook_retained_backings[slot].reserved = 0;
            g_hook_retained_backing_count = slot + 1;
            wr<u64>(g_hook_backing_header_data_ptr_addr, 0);
            g_hook_backing_retained = 1;
            g_hook_alias_destroy_suppressed++;
            return;
        }
        // Capacity should have been checked before arming. If it changed or an
        // invariant is violated, never silently free a buffer already borrowed
        // by reconstructed state; mark fail-closed and retain it anyway.
        wr<u64>(g_hook_backing_header_data_ptr_addr, 0);
        g_hook_backing_retained = 1;
        g_hook_alias_guard_misses++;
        g_general_fail_closed++;
        g_hook_alias_destroy_suppressed++;
        return;
    }

    const i64 t0 = p ? qpc_now() : 0;
    g_clone_destroy_orig(data, count);
    if (p) { g_clone_destroy_ticks += qpc_now() - t0; g_clone_destroy_calls++; }
}

extern "C" u64 PCL_MS_ABI pcl_mw_actor_make_hook(void* forge, void* applied) {
    const bool p = (g_armed != 0 && g_in_child_d > 0);
    const i64 t0 = p ? qpc_now() : 0;
    if (p) g_in_actor_make++;
    u64 r = g_actor_make_orig(forge, applied);
    if (p) {
        g_in_actor_make--;
        g_actor_make_ticks += qpc_now() - t0;
        g_actor_make_calls++;
    }
    return r;
}

extern "C" u64 PCL_MS_ABI pcl_mw_actor_link_hook(void* parent, void* child, void* mode) {
    const bool p = (g_armed != 0 && g_in_child_d > 0);
    const i64 t0 = p ? qpc_now() : 0;
    if (p) g_in_actor_link++;
    u64 r = g_actor_link_orig(parent, child, mode);
    if (p) {
        g_in_actor_link--;
        g_actor_link_ticks += qpc_now() - t0;
        g_actor_link_calls++;
    }
    return r;
}

extern "C" void PCL_MS_ABI pcl_mw_child_refresh_hook(void* actor, u8 a, u8 b) {
    const bool defer = (g_armed != 0 && g_in_child_d > 0 &&
                        g_defer_refresh_active != 0 && g_in_actor_link > 0);
    if (defer) {
        const u64 forge = (u64)g_current_forge;
        const u64 root = forge ? rd<u64>(forge + 0x320) : 0;
        if (root) {
            g_deferred_refresh_calls++;
            return;
        }
    }
    g_child_refresh_orig(actor, a, b);
}

extern "C" u64 PCL_MS_ABI pcl_mw_link_notify_hook(void* a1, void* a2, void* a3, void* a4) {
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_in_actor_link > 0);
    const i64 t0 = p ? qpc_now() : 0;
    u64 r = g_link_notify_orig(a1,a2,a3,a4);
    if (p) { g_link_notify_ticks += qpc_now() - t0; g_link_notify_calls++; }
    return r;
}

extern "C" u64 PCL_MS_ABI pcl_mw_link_map_hook(void* a1, void* a2, void* a3, void* a4) {
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_in_actor_link > 0);
    const i64 t0 = p ? qpc_now() : 0;
    u64 r = g_link_map_orig(a1,a2,a3,a4);
    if (p) { g_link_map_ticks += qpc_now() - t0; g_link_map_calls++; }
    return r;
}

extern "C" u64 PCL_MS_ABI pcl_mw_actor_spawn_hook(void* a1, void* a2, void* a3, void* a4, void* a5) {
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_in_actor_make > 0);
    const i64 t0 = p ? qpc_now() : 0;
    u64 r = g_actor_spawn_orig(a1,a2,a3,a4,a5);
    if (p) { g_actor_spawn_ticks += qpc_now() - t0; g_actor_spawn_calls++; }
    return r;
}

extern "C" u64 PCL_MS_ABI pcl_mw_actor_resolve_hook(void* a1, void* a2) {
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_in_actor_make > 0);
    const i64 t0 = p ? qpc_now() : 0;
    u64 r = g_actor_resolve_orig(a1,a2);
    if (p) { g_actor_resolve_ticks += qpc_now() - t0; g_actor_resolve_calls++; }
    return r;
}

extern "C" u64 PCL_MS_ABI pcl_mw_actor_data_hook(void* a1, void* a2, void* a3) {
    const bool p = (g_armed != 0 && g_in_child_d > 0 && g_in_actor_make > 0);
    const i64 t0 = p ? qpc_now() : 0;
    u64 r = g_actor_data_orig(a1,a2,a3);
    if (p) { g_actor_data_ticks += qpc_now() - t0; g_actor_data_calls++; }
    return r;
}
extern "C" u64 PCL_MS_ABI pcl_mw_child_e_hook(void* a1) {
    const bool p = profile_child(); i64 t0 = p ? qpc_now() : 0;
    u64 r = g_child_e_orig(a1);
    if (p) { g_child_e_ticks += qpc_now() - t0; g_child_e_count++; }
    return r;
}

static bool install_one(u64 target, u32 stolen, const u8* sig, u32 sig_len, u8* tramp, u64 hook, void** orig_out) {
    // 14 bytes are required for the register-preserving absolute jump.
    if (!target || stolen < 14 || !tramp || !hook || !orig_out) return false;
    if (!bytes_match(target, sig, sig_len)) return false;

    ULONG old_tramp = 0, old_target = 0;
    if (!protect_rw_x(tramp, 64, &old_tramp)) return false;
    if (!protect_rw_x((void*)target, stolen, &old_target)) {
        restore_protect(tramp, 64, old_tramp);
        return false;
    }

    for (u32 i = 0; i < stolen; ++i) tramp[i] = rd<u8>(target + i);
    emit_abs_jump(tramp + stolen, target + stolen);
    for (u32 i = stolen + 14; i < 64; ++i) tramp[i] = 0xCC;
    flush_code(tramp, 64);

    u8 patch[32];
    for (u32 i = 0; i < 32; ++i) patch[i] = 0x90;
    emit_abs_jump(patch, hook);
    for (u32 i = 0; i < stolen; ++i) wr<u8>(target + i, patch[i]);
    flush_code((void*)target, stolen);

    restore_protect((void*)target, stolen, old_target);
    (void)old_tramp; // trampoline intentionally remains executable
    *orig_out = (void*)tramp;
    return true;
}

static int install_hooks() {
    if (g_installed) return 1;
    const u64 base = get_main_module_base();
    if (!base) return -2;
    if (rd<u16>(base + 0x00) != 0x5A4D) return -3;
    const u32 peoff = rd<u32>(base + 0x3C);
    if (rd<u32>(base + peoff) != 0x00004550u) return -3;
    const u64 size_of_image_off = base + peoff + 0x18 + 0x38;
    if (rd<u32>(size_of_image_off) != 0x090A0000u) return -4;
    if (!resolve_ntdll()) return -5;

    const u64 enter = base + 0x045A1FA0ull;
    const u64 seam  = base + 0x045AF640ull;
    const u64 child_a = base + 0x045C73B0ull;
    const u64 child_b = base + 0x045E89A0ull;
    const u64 child_c = base + 0x045E8EA0ull;
    const u64 child_d = base + 0x045BAF80ull;
    const u64 child_e = base + 0x045C7950ull;
    // Hook the non-zero-count path of the FAppliedSwordPart array copy routine.
    // +0x9 skips its initial count==0 conditional branch, keeping the trampoline relocation-free.
    const u64 copy_nonzero = base + 0x0453F679ull;
    const u64 clone_alloc = base + 0x010D0AB0ull;
    // FAppliedSwordPart array destructor's non-zero path; +4 skips test/jz.
    const u64 clone_destroy_nonzero = base + 0x0452F0C4ull;
    const u64 raw_free = base + 0x011531C0ull;
    const u64 actor_make = base + 0x0459E680ull;
    const u64 actor_link = base + 0x045E9D30ull;
    const u64 child_refresh = base + 0x045F3BD0ull;
    const u64 link_notify = base + 0x03412800ull;
    const u64 link_map = base + 0x045C97A0ull;
    const u64 actor_spawn = base + 0x039B5920ull;
    const u64 actor_resolve = base + 0x045ACF20ull;
    const u64 actor_data = base + 0x045A59A0ull;

    const u8 enter_sig[16] = {0x48,0x89,0x5C,0x24,0x18,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57};
    const u8 seam_sig[15]  = {0x48,0x8B,0xC4,0x48,0x89,0x58,0x10,0x48,0x89,0x70,0x18,0x48,0x89,0x78,0x20};
    const u8 child_a_sig[16] = {0x48,0x8B,0xC4,0x48,0x89,0x58,0x18,0x48,0x89,0x48,0x08,0x55,0x56,0x57,0x41,0x54};
    const u8 child_b_sig[20] = {0x48,0x89,0x5C,0x24,0x18,0x55,0x56,0x57,0x41,0x56,0x41,0x57,0x48,0x8D,0xAC,0x24,0x80,0xFE,0xFF,0xFF};
    const u8 child_c_sig[16] = {0x40,0x57,0x48,0x83,0xEC,0x20,0x48,0x89,0x91,0xC0,0x02,0x00,0x00,0x48,0x8B,0xF9};
    const u8 child_d_sig[15] = {0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20};
    const u8 child_e_sig[18] = {0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x56,0x57,0x41,0x56,0x48,0x83,0xEC,0x40};
    const u8 copy_sig[15] = {0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18};
    const u8 clone_alloc_sig[15] = {0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18};
    const u8 clone_destroy_sig[19] = {0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,0xEC,0x20,0x8B,0xFA,0x48,0x8D,0x99,0xD0,0x00,0x00,0x00};
    const u8 raw_free_sig[15] = {0x48,0x85,0xC9,0x74,0x2E,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B};
    const u8 actor_make_sig[16] = {0x48,0x89,0x5C,0x24,0x18,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57};
    const u8 actor_link_sig[15] = {0x48,0x89,0x5C,0x24,0x20,0x44,0x88,0x44,0x24,0x18,0x48,0x89,0x54,0x24,0x10};
    const u8 child_refresh_sig[14] = {0x48,0x89,0x5C,0x24,0x18,0x88,0x54,0x24,0x10,0x55,0x56,0x57,0x41,0x54};
    const u8 link_notify_sig[15] = {0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xEC,0x20};
    const u8 link_map_sig[20] = {0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x41,0x54,0x41,0x55};
    const u8 actor_spawn_sig[15] = {0x48,0x8B,0xC4,0x48,0x89,0x58,0x08,0x57,0x48,0x81,0xEC,0xA0,0x00,0x00,0x00};
    const u8 actor_resolve_sig[15] = {0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xEC,0x50};
    const u8 actor_data_sig[16] = {0x48,0x89,0x5C,0x24,0x20,0x55,0x57,0x41,0x56,0x48,0x83,0xEC,0x20,0x49,0x8B,0xD8};

    if (!bytes_match(raw_free, raw_free_sig, 15)) return -46;
    g_raw_free = (RawFreeFn)raw_free;

    if (!install_one(enter, 16, enter_sig, 16, g_enter_tramp, (u64)&pcl_mw_enter_hook, (void**)&g_enter_orig)) return -11;
    if (!install_one(seam, 15, seam_sig, 15, g_seam_tramp, (u64)&pcl_mw_seam_hook, (void**)&g_seam_orig)) return -12;
    if (!install_one(child_a, 16, child_a_sig, 16, g_child_a_tramp, (u64)&pcl_mw_child_a_hook, (void**)&g_child_a_orig)) return -21;
    if (!install_one(child_b, 20, child_b_sig, 20, g_child_b_tramp, (u64)&pcl_mw_child_b_hook, (void**)&g_child_b_orig)) return -22;
    if (!install_one(child_c, 16, child_c_sig, 16, g_child_c_tramp, (u64)&pcl_mw_child_c_hook, (void**)&g_child_c_orig)) return -23;
    if (!install_one(child_d, 15, child_d_sig, 15, g_child_d_tramp, (u64)&pcl_mw_child_d_hook, (void**)&g_child_d_orig)) return -24;
    if (!install_one(child_e, 18, child_e_sig, 18, g_child_e_tramp, (u64)&pcl_mw_child_e_hook, (void**)&g_child_e_orig)) return -25;
    if (!install_one(copy_nonzero, 15, copy_sig, 15, g_copy_tramp, (u64)&pcl_mw_copy_hook, (void**)&g_copy_orig)) return -31;
    if (!install_one(clone_alloc, 15, clone_alloc_sig, 15, g_clone_alloc_tramp, (u64)&pcl_mw_clone_alloc_hook, (void**)&g_clone_alloc_orig)) return -32;
    if (!install_one(clone_destroy_nonzero, 19, clone_destroy_sig, 19, g_clone_destroy_tramp, (u64)&pcl_mw_clone_destroy_hook, (void**)&g_clone_destroy_orig)) return -33;
    if (!install_one(actor_make, 16, actor_make_sig, 16, g_actor_make_tramp, (u64)&pcl_mw_actor_make_hook, (void**)&g_actor_make_orig)) return -34;
    if (!install_one(actor_link, 15, actor_link_sig, 15, g_actor_link_tramp, (u64)&pcl_mw_actor_link_hook, (void**)&g_actor_link_orig)) return -35;
    if (!install_one(child_refresh, 14, child_refresh_sig, 14, g_child_refresh_tramp, (u64)&pcl_mw_child_refresh_hook, (void**)&g_child_refresh_orig)) return -36;
    if (!install_one(link_notify, 15, link_notify_sig, 15, g_link_notify_tramp, (u64)&pcl_mw_link_notify_hook, (void**)&g_link_notify_orig)) return -41;
    if (!install_one(link_map, 20, link_map_sig, 20, g_link_map_tramp, (u64)&pcl_mw_link_map_hook, (void**)&g_link_map_orig)) return -42;
    if (!install_one(actor_spawn, 15, actor_spawn_sig, 15, g_actor_spawn_tramp, (u64)&pcl_mw_actor_spawn_hook, (void**)&g_actor_spawn_orig)) return -43;
    if (!install_one(actor_resolve, 15, actor_resolve_sig, 15, g_actor_resolve_tramp, (u64)&pcl_mw_actor_resolve_hook, (void**)&g_actor_resolve_orig)) return -44;
    if (!install_one(actor_data, 16, actor_data_sig, 16, g_actor_data_tramp, (u64)&pcl_mw_actor_data_hook, (void**)&g_actor_data_orig)) return -45;

    g_installed = 1;
    return 1;
}

// Lua 5.4 x64 minimal return helpers; same layout as the proven PCL bridge.
static int lua_push_integer(void* state, i64 value) {
    if (!state) return 0;
    const u64 L = (u64)state;
    const u64 top = rd<u64>(L + 0x10);
    if (!top) return 0;
    *(volatile i64*)(top + 0x00) = value;
    *(volatile u8*)(top + 0x08) = 3u;
    *(volatile u64*)(L + 0x10) = top + 16ull;
    return 1;
}

extern "C" __declspec(dllexport) int pcl_mw_prof_install(void* L) {
    return lua_push_integer(L, (i64)install_hooks());
}

extern "C" __declspec(dllexport) int pcl_mw_prof_arm(void* L) {
    if (!g_installed) return lua_push_integer(L, -1);
    reset_profile_counters();
    if (g_alias_requested) {
        g_alias_patch_status = (i64)apply_alias_patches();
        // A signature/protection failure is safe if rollback completed; simply
        // continue with stock array ownership + deferred refresh. If rollback
        // itself could not restore every modified site, refuse to arm so the
        // PCL seam will not run through a partial patch state.
        if (g_alias_patch_status != 1 && g_alias_patch_mask != 0) {
            g_alias_requested = 0;
            return lua_push_integer(L, -2);
        }
    } else {
        restore_alias_patches();
        if (g_alias_patch_mask != 0) return lua_push_integer(L, -3);
    }
    g_arm_qpc = qpc_now();
    g_armed = 1;
    return lua_push_integer(L, 1);
}

extern "C" __declspec(dllexport) int pcl_mw_prof_disarm(void* L) {
    g_armed = 0;
    restore_alias_patches();
    g_alias_requested = 0;
    return lua_push_integer(L, g_alias_patch_mask ? -2 : 1);
}

extern "C" __declspec(dllexport) int pcl_mw_prof_alias_on(void* L) {
    g_alias_requested = 1;
    return lua_push_integer(L, 1);
}

extern "C" __declspec(dllexport) int pcl_mw_prof_alias_off(void* L) {
    g_alias_requested = 0;
    if (!g_armed) restore_alias_patches();
    return lua_push_integer(L, g_alias_patch_mask ? -2 : 1);
}

extern "C" __declspec(dllexport) int pcl_mw_prof_read(void* L) {
    // Returns historical fields plus appended diagnostics. 15.11.57 adds three
    // persistent-backing fields after all existing indices.
    int n = 0;
    n += lua_push_integer(L, g_installed);
    n += lua_push_integer(L, g_armed);
    n += lua_push_integer(L, g_enter_count);
    n += lua_push_integer(L, g_seam_count);
    n += lua_push_integer(L, (g_enter_begin && g_arm_qpc) ? qpc_to_us(g_enter_begin - g_arm_qpc) : 0);
    n += lua_push_integer(L, (g_enter_end && g_enter_begin) ? qpc_to_us(g_enter_end - g_enter_begin) : 0);
    n += lua_push_integer(L, (g_seam_end && g_seam_begin) ? qpc_to_us(g_seam_end - g_seam_begin) : 0);
    n += lua_push_integer(L, g_last_piece);
    n += lua_push_integer(L, g_child_a_count); n += lua_push_integer(L, qpc_to_us(g_child_a_ticks));
    n += lua_push_integer(L, g_child_b_count); n += lua_push_integer(L, qpc_to_us(g_child_b_ticks));
    n += lua_push_integer(L, g_child_c_count); n += lua_push_integer(L, qpc_to_us(g_child_c_ticks));
    n += lua_push_integer(L, g_child_d_count); n += lua_push_integer(L, qpc_to_us(g_child_d_ticks));
    n += lua_push_integer(L, g_child_e_count); n += lua_push_integer(L, qpc_to_us(g_child_e_ticks));
    n += lua_push_integer(L, g_applied_count);
    n += lua_push_integer(L, g_blade_count);
    n += lua_push_integer(L, g_copy_calls);
    n += lua_push_integer(L, g_copy_elements);
    n += lua_push_integer(L, qpc_to_us(g_copy_ticks));
    n += lua_push_integer(L, g_clone_alloc_calls);
    n += lua_push_integer(L, qpc_to_us(g_clone_alloc_ticks));
    n += lua_push_integer(L, g_clone_destroy_calls);
    n += lua_push_integer(L, qpc_to_us(g_clone_destroy_ticks));
    n += lua_push_integer(L, g_actor_make_calls);
    n += lua_push_integer(L, qpc_to_us(g_actor_make_ticks));
    n += lua_push_integer(L, g_actor_link_calls);
    n += lua_push_integer(L, qpc_to_us(g_actor_link_ticks));
    n += lua_push_integer(L, PCL_MW_DEFER_THRESHOLD);
    n += lua_push_integer(L, g_deferred_refresh_calls);
    n += lua_push_integer(L, g_final_refresh_calls);
    n += lua_push_integer(L, qpc_to_us(g_final_refresh_ticks));
    n += lua_push_integer(L, g_final_refresh_root);
    n += lua_push_integer(L, g_link_notify_calls);
    n += lua_push_integer(L, qpc_to_us(g_link_notify_ticks));
    n += lua_push_integer(L, g_link_map_calls);
    n += lua_push_integer(L, qpc_to_us(g_link_map_ticks));
    n += lua_push_integer(L, g_actor_spawn_calls);
    n += lua_push_integer(L, qpc_to_us(g_actor_spawn_ticks));
    n += lua_push_integer(L, g_actor_resolve_calls);
    n += lua_push_integer(L, qpc_to_us(g_actor_resolve_ticks));
    n += lua_push_integer(L, g_actor_data_calls);
    n += lua_push_integer(L, qpc_to_us(g_actor_data_ticks));
    n += lua_push_integer(L, g_alias_requested);
    n += lua_push_integer(L, g_alias_active);
    n += lua_push_integer(L, g_alias_patch_status);
    n += lua_push_integer(L, g_alias_enable_count);
    n += lua_push_integer(L, g_general_load_seq);
    n += lua_push_integer(L, g_general_last_pre_applied);
    n += lua_push_integer(L, g_general_last_source_mode);
    n += lua_push_integer(L, g_general_last_alias_status);
    n += lua_push_integer(L, g_general_last_alias_used);
    n += lua_push_integer(L, g_general_last_restore_ok);
    n += lua_push_integer(L, g_general_fail_closed);
    // 15.11.47 appended detour-owned zero-copy diagnostics.
    n += lua_push_integer(L, g_hook_alias_zero_copy_calls);
    n += lua_push_integer(L, g_hook_alias_zero_copy_elements);
    n += lua_push_integer(L, (i64)g_hook_alias_peak);
    n += lua_push_integer(L, g_hook_alias_destroy_suppressed);
    n += lua_push_integer(L, g_hook_alias_guard_misses);
    n += lua_push_integer(L, g_hook_alias_fallback_copies);
    // Reserve the ten historical 15.11.49 actor-helper slots even though the
    // helper detours are disabled in this profiler core. This keeps every old
    // Lua field index stable before adding 15.11.57 diagnostics.
    for (int i=0;i<10;i++) n += lua_push_integer(L, 0);
    // 15.11.57 persistent-backing diagnostics.
    n += lua_push_integer(L, g_hook_backing_stock_copies);
    n += lua_push_integer(L, g_hook_backing_retained);
    n += lua_push_integer(L, (i64)g_hook_retained_backing_count);
    return n;
}
