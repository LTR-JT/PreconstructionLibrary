// Win64 compiler portability; native address guards and behavior retained.
#ifdef _MSC_VER
#include <intrin.h>
#define PCL_MS_ABI
#define PCL_ALIGN(n) __declspec(align(n))
#else
#define PCL_MS_ABI __attribute__((ms_abi))
#define PCL_ALIGN(n) __attribute__((aligned(n)))
#endif
// PCL Phase 15.11.98 - guarded A20 four-array output cache prototype on the stable 15.11.90 hook set.
// 15.11.96 proved all four mutable A20 arrays are byte-stable for promoted repeat sources.
// 15.11.98 reuses those proven outputs from a bounded DLL-owned arena, with stock A20 fallback
// for unproven/unstable sources, guard failures, arena exhaustion, and every 128th canary call.
// 15.11.79 proved that update tail 0x364A270 costs only ~3% of update time;
// roughly 0.88 s remains before the tail. 15.11.80 measures the two hot-path
// virtual calls at vtable slots +0x2D0 and +0x2B0 by temporarily swapping only
// those vtable pointers during the synchronous seam. No target function prologue
// or relative machine instruction is copied or detoured.
// 15.11.69-72 proved that H4 source reuse is extreme (99%+) and that ~97% of
// repeat H4 time belongs to sources whose vertex payload is stable across stock outputs.
// but static analysis also shows that H4 writes source-derived geometry arrays into
// each destination actor and then performs actor/component-specific finalization.
//
// 15.11.77 keeps the proven 15.11.73 selective vertex cache, the 15.11.74
// post-loop timing, and the 15.11.75 nested component-build profiler. 15.11.75
// showed that the component builder's update helper (RVA 0x40119F0) dominates the
// remaining cost. This phase adds a second measurement-only layer that times selected
// direct callees of that update helper with first-level exclusivity: when one profiled
// direct helper invokes another, the nested helper is not counted again. This makes
// the new direct-helper sum comparable to the parent update time without overlap. The
// high-frequency 15.11.75 grow/payload/recalc/tail detours are deliberately not installed
// in this phase; only the update wrapper remains, avoiding observer overhead.
//
// 15.11.73 keeps H4's bounds, index-array copy/allocation, actor allocation, and
// component finalization stock. It adds a second seam-scoped mid-function detour at
// H4+0x15D (RVA 0x45F81DD), immediately after the stock vertex TArray allocation.
// A source is not eligible until EIGHT stock outputs in the same rebuild have the same
// vertex count/hash. Eligible source vertex bytes are copied into a DLL-owned bounded
// cache. Later calls copy those bytes into that actor's freshly allocated vertex TArray
// and jump over only the expensive source->vertex conversion loop; all post-loop stock
// finalization remains untouched. Every 128th cached call is a stock canary and may
// permanently demote the source if its vertex payload changes. Bounds and index data
// are never cached. Both H4 patches are restored before handoff.
// Loaded by Lua package.loadlib. It uses only the stable Lua 5.4 internal
// stack layout to read two integer arguments and return one integer status;
// no Lua/CRT/Win32 imports are required.

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef long long i64;
typedef int i32;
typedef long NTSTATUS;
typedef unsigned long ULONG;
typedef unsigned long long SIZE_T;

extern "C" { int _fltused = 0; }

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
    const u64 head = ldr + 0x20; // InMemoryOrderModuleList
    const u64 first_link = rd<u64>(head);
    if (!first_link || first_link == head) return 0;
    // first_link points to LDR_DATA_TABLE_ENTRY.InMemoryOrderLinks (+0x10).
    // DllBase lives at entry +0x30 -> first_link +0x20.
    return rd<u64>(first_link + 0x20);
}

// ---------------------------------------------------------------------------
// Phase 15.11.80 - temporary H4 entry + vertex-loop + post-loop + update-tail profiling patches, resolved from ntdll without
// imports so the bridge retains its existing no-import deployment model.

static bool ascii_eq(const char* a, const char* b) {
    if (!a || !b) return false;
    while (*a && *b) {
        if (*a != *b) return false;
        ++a; ++b;
    }
    return *a == 0 && *b == 0;
}

static bool unicode_basename_eq(u64 us_addr, const char* ascii_lower) {
    const u16 len_bytes = rd<u16>(us_addr + 0x0);
    const u64 buf = rd<u64>(us_addr + 0x8);
    if (!buf) return false;
    const u32 n = (u32)(len_bytes / 2);
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
            if (fn_rva >= exp_rva && fn_rva < exp_rva + exp_size) return 0;
            return module + fn_rva;
        }
    }
    return 0;
}

typedef NTSTATUS (PCL_MS_ABI *NtProtectVirtualMemoryFn)(
    void*, void**, SIZE_T*, ULONG, ULONG*);
typedef NTSTATUS (PCL_MS_ABI *NtFlushInstructionCacheFn)(
    void*, void*, ULONG);
typedef NTSTATUS (PCL_MS_ABI *NtQueryPerformanceCounterFn)(i64*, i64*);

static NtProtectVirtualMemoryFn g_h4_protect = 0;
static NtFlushInstructionCacheFn g_h4_flush = 0;
static NtQueryPerformanceCounterFn g_h4_qpc = 0;
static i64 g_h4_qpf = 0;

static bool h4_resolve_patch_api() {
    if (g_h4_protect && g_h4_flush) return true;
    const u64 ntdll = find_loaded_module("ntdll.dll");
    if (!ntdll) return false;
    g_h4_protect = (NtProtectVirtualMemoryFn)export_by_name(ntdll, "NtProtectVirtualMemory");
    g_h4_flush = (NtFlushInstructionCacheFn)export_by_name(ntdll, "NtFlushInstructionCache");
    g_h4_qpc = (NtQueryPerformanceCounterFn)export_by_name(ntdll, "NtQueryPerformanceCounter");
    g_h4_qpf = 0;
    if (g_h4_qpc) {
        i64 now = 0, freq = 0;
        if (g_h4_qpc(&now, &freq) >= 0 && freq > 0) g_h4_qpf = freq;
    }
    // Timing is diagnostic only; lack of QPC must never block the safe pass-through.
    return g_h4_protect && g_h4_flush;
}

static inline i64 h4_qpc_now() {
    i64 v = 0;
    if (g_h4_qpc) g_h4_qpc(&v, 0);
    return v;
}

static i64 h4_qpc_to_us(i64 ticks) {
    if (ticks <= 0 || g_h4_qpf <= 0) return 0;
    return (ticks * 1000000ll) / g_h4_qpf;
}

static bool h4_protect_rwx(void* p, SIZE_T n, ULONG* oldp) {
    if (!g_h4_protect || !p || !n) return false;
    void* base = p;
    SIZE_T size = n;
    ULONG oldv = 0;
    const NTSTATUS st = g_h4_protect(
        (void*)(i64)-1, &base, &size, 0x40u /* PAGE_EXECUTE_READWRITE */, &oldv);
    if (st < 0) return false;
    if (oldp) *oldp = oldv;
    return true;
}

static void h4_restore_protection(void* p, SIZE_T n, ULONG oldp) {
    if (!g_h4_protect || !p || !n) return;
    void* base = p;
    SIZE_T size = n;
    ULONG ignored = 0;
    g_h4_protect((void*)(i64)-1, &base, &size, oldp, &ignored);
}

static void h4_flush_code(void* p, ULONG n) {
    if (g_h4_flush) g_h4_flush((void*)(i64)-1, p, n);
}

static void h4_emit_abs_jump(u8* out, u64 dst) {
    out[0] = 0xFF; out[1] = 0x25;
    out[2] = 0x00; out[3] = 0x00; out[4] = 0x00; out[5] = 0x00;
    *(u64*)(out + 6) = dst;
}

static bool h4_bytes_match(u64 p, const u8* sig, u32 n) {
    for (u32 i = 0; i < n; ++i)
        if (rd<u8>(p + (u64)i) != sig[i]) return false;
    return true;
}

typedef u64 (PCL_MS_ABI *H4Fn)(void*, void*);
PCL_ALIGN(64) static u8 g_h4_scope_tramp[64];
static H4Fn g_h4_scope_orig = 0;
static u8 g_h4_scope_saved[15];
static volatile i64 g_h4_scope_calls = 0;
static volatile i64 g_h4_scope_install_status = 0;
static volatile i64 g_h4_scope_restore_status = 0;
static volatile i64 g_h4_scope_active = 0;
static volatile i64 g_h4_scope_stock_restored = 1;
static volatile u64 g_h4_scope_owner_teb = 0;
static volatile i64 g_h4_profile_calls = 0;
static volatile i64 g_h4_other_thread_calls = 0;

// 15.11.69: bounded, allocation-free source-pointer reuse table. H4's second
// argument is only used as an identity key. It is never dereferenced here.
static const u32 H4_SOURCE_CAP = 8192u;
struct H4SourceEntry {
    u64 source;
    i64 ticks;
    u32 calls;
    u32 fp_state; // 0=none, 1=captured, 2=full-payload validated, 3=full-payload mismatch
    u32 geometry_state; // 0=none/unseen, 1=awaiting second sample, 2=geometry stable, 3=geometry unstable
    u32 reserved;
    u64 bounds_hash;
    u64 index_hash;
    u64 vertex_hash;
    u32 index_num;
    u32 vertex_num;

    // 15.11.73 selective vertex-cache proof/ownership state.
    u64 proof_vertex_hash;
    u64 cache_offset;
    u64 cache_bytes;
    u32 proof_vertex_num;
    u32 proof_matches;
    u32 cache_state; // 0=unseen, 1=proving, 2=ready, 3=rejected/demoted, 4=arena unavailable
    u32 fast_since_canary;

    // 15.11.96 measurement-only proof for all four mutable arrays at
    // hotspot 0x3B99A20. Callsite ABI:
    //   RCX = TArray<12-byte records>*, RDX/R8/R9 = TArray<int32>*.
    // The prior 15.11.95 proof covered only R8/R9; no cache/reuse occurs here.
    u64 a20_hash0;
    u64 a20_hash1;
    u64 a20_hash2;
    u64 a20_hash3;
    u32 a20_num0;
    u32 a20_num1;
    u32 a20_num2;
    u32 a20_num3;
    u32 a20_state; // 0=unseen, 1=proving, 2=ready, 3=rejected/demoted
    u32 a20_matches;
    u32 a20_since_canary;
    u32 a20_reserved; // 0=no cached bytes, 1=cache ready, 2=arena unavailable
    u64 a20_cache_off0;
    u64 a20_cache_off1;
    u64 a20_cache_off2;
    u64 a20_cache_off3;
    u64 a20_cache_bytes0;
    u64 a20_cache_bytes1;
    u64 a20_cache_bytes2;
    u64 a20_cache_bytes3;

    // 15.11.100 guarded cache proof/runtime for the 48-byte local bounds produced
    // by 0x1CFF490 after its inline triangle scan. The cache owns only six POD qwords;
    // F490's object remains game-owned and its stock finalizer still runs.
    u64 f490_bounds_hash;
    u64 f490_bounds_cache[6];
    u32 f490_state; // 0=unseen, 1=proving, 2=ready, 3=rejected
    u32 f490_matches;
    u32 f490_since_canary;
    u32 f490_reserved; // 0=no cache bytes yet, 1=48-byte cache captured
};
static H4SourceEntry g_h4_sources[H4_SOURCE_CAP];
static volatile i64 g_h4_unique_sources = 0;
static volatile i64 g_h4_repeat_calls = 0;
static volatile i64 g_h4_first_ticks = 0;
static volatile i64 g_h4_repeat_ticks = 0;
static volatile i64 g_h4_total_ticks = 0;
static volatile i64 g_h4_null_source_calls = 0;
static volatile i64 g_h4_table_overflow = 0;
static volatile u32 g_h4_max_calls_per_source = 0;
static volatile u64 g_h4_max_source_ptr = 0;
static volatile i64 g_h4_max_source_ticks = 0;
static volatile u64 g_h4_hot_source_ptr = 0;
static volatile u32 g_h4_hot_source_calls = 0;
static volatile i64 g_h4_hot_source_ticks = 0;

// 15.11.71 component-level output-payload stability telemetry. These counters describe only
// fingerprinting/validation and never influence the stock H4 result.
static volatile i64 g_h4_fp_sources_captured = 0;
static volatile i64 g_h4_fp_sources_validated = 0;
static volatile i64 g_h4_fp_sources_mismatch = 0;
static volatile i64 g_h4_fp_guard_fail = 0;
static volatile i64 g_h4_fp_checks = 0;
static volatile i64 g_h4_fp_hash_ticks = 0;
static volatile i64 g_h4_fp_index_bytes = 0;
static volatile i64 g_h4_fp_vertex_bytes = 0;
static volatile u64 g_h4_fp_first_mismatch_source = 0;
static volatile u32 g_h4_fp_first_mismatch_code = 0;
static volatile i64 g_h4_fp_geometry_validated = 0;
static volatile i64 g_h4_fp_geometry_mismatch = 0;
static volatile i64 g_h4_fp_bounds_only_mismatch = 0;
static volatile i64 g_h4_fp_bounds_mismatch = 0;
static volatile i64 g_h4_fp_index_num_mismatch = 0;
static volatile i64 g_h4_fp_vertex_num_mismatch = 0;
static volatile i64 g_h4_fp_index_hash_mismatch = 0;
static volatile i64 g_h4_fp_vertex_hash_mismatch = 0;
static volatile u64 g_h4_fp_first_geometry_mismatch_source = 0;
static volatile u32 g_h4_fp_first_geometry_mismatch_code = 0;

// 15.11.72 cache-benefit classification. These counters begin only after a source
// has been proven stable or unstable by two stock H4 outputs in the current seam.
// They quantify the work a future selective cache could actually avoid.
static volatile i64 g_h4_stable_post_calls = 0;
static volatile i64 g_h4_stable_post_ticks = 0;
static volatile i64 g_h4_unstable_post_calls = 0;
static volatile i64 g_h4_unstable_post_ticks = 0;
static volatile i64 g_h4_unresolved_repeat_calls = 0;
static volatile i64 g_h4_unresolved_repeat_ticks = 0;


// 15.11.73 bounded selective vertex payload cache. This cache owns only raw copied
// vertex bytes; actor TArray headers/pointers always remain stock-owned and unique.
static const u64 H4_VERTEX_CACHE_CAP = 16ull * 1024ull * 1024ull;
static const u32 H4_CACHE_PROOF_MATCHES = 8u;
static const u32 H4_CACHE_CANARY_INTERVAL = 128u;
PCL_ALIGN(64) static u8 g_h4_vertex_cache[H4_VERTEX_CACHE_CAP];
static volatile u64 g_h4_vertex_cache_used = 0;
static H4SourceEntry* volatile g_h4_current_fast_entry = 0;
static volatile i64 g_h4_current_fast_used = 0;
// 15.11.95: points at the source entry only while the already-hooked H4 call
// is executing on the seam owner thread. Existing nested wrappers may observe
// it; no additional game code site is patched.
static H4SourceEntry* volatile g_h4_current_scope_entry = 0;

static volatile i64 g_h4_cache_promoted_sources = 0;
static volatile i64 g_h4_cache_rejected_sources = 0;
static volatile i64 g_h4_cache_late_demotions = 0;
static volatile i64 g_h4_cache_fast_calls = 0;
static volatile i64 g_h4_cache_fast_bytes = 0;
static volatile i64 g_h4_cache_copy_ticks = 0;
static volatile i64 g_h4_cache_mid_guard_fail = 0;
static volatile i64 g_h4_cache_canary_calls = 0;
static volatile i64 g_h4_cache_canary_mismatch = 0;
static volatile i64 g_h4_cache_proof_checks = 0;
static volatile i64 g_h4_cache_proof_ticks = 0;
static volatile i64 g_h4_cache_arena_rejects = 0;

PCL_ALIGN(64) static u8 g_h4_loop_tramp[64];
PCL_ALIGN(64) static u8 g_h4_loop_dispatch[128];
static u8 g_h4_loop_saved[16];
static volatile i64 g_h4_loop_install_status = 0;
static volatile i64 g_h4_loop_restore_status = 0;
static volatile i64 g_h4_loop_active = 0;
static volatile i64 g_h4_loop_stock_restored = 1;
static volatile u64 g_h4_loop_fast_cont = 0;


// 15.11.74 post-loop callsite profiler. These four patches are measurement-only and
// live only during the synchronous rebuild seam. Each dispatch replays the exact stock
// argument-setup bytes, calls a same-ABI timing wrapper which forwards to the original
// target, then resumes at the first untouched stock instruction.
static volatile i64 g_h4_post_install_status = 0;
static volatile i64 g_h4_post_restore_status = 0;
static volatile i64 g_h4_post_active = 0;
static volatile i64 g_h4_post_stock_restored = 1;
static volatile i64 g_h4_post_vertex_copy_calls = 0;
static volatile i64 g_h4_post_vertex_copy_ticks = 0;
static volatile i64 g_h4_post_index_copy_calls = 0;
static volatile i64 g_h4_post_index_copy_ticks = 0;
static volatile i64 g_h4_post_component_build_calls = 0;
static volatile i64 g_h4_post_component_build_ticks = 0;
static volatile i64 g_h4_post_component_final_calls = 0;
static volatile i64 g_h4_post_component_final_ticks = 0;

static u8 g_h4_post_vertex_copy_saved[19];
static u8 g_h4_post_index_copy_saved[21];
static u8 g_h4_post_build_saved[14];
static u8 g_h4_post_final_saved[15];
PCL_ALIGN(64) static u8 g_h4_post_vertex_copy_dispatch[96];
PCL_ALIGN(64) static u8 g_h4_post_index_copy_dispatch[96];
PCL_ALIGN(64) static u8 g_h4_post_build_dispatch[96];
PCL_ALIGN(64) static u8 g_h4_post_final_dispatch[96];

typedef u64 (PCL_MS_ABI *H4BulkCopyFn)(void*, const void*, u64);
typedef u64 (PCL_MS_ABI *H4ComponentBuildFn)(void*, u64, void*);
typedef u64 (PCL_MS_ABI *H4ComponentFinalFn)(void*, u64);
static H4BulkCopyFn g_h4_post_bulk_copy_orig = 0;
static H4ComponentBuildFn g_h4_post_component_build_orig = 0;
static H4ComponentFinalFn g_h4_post_component_final_orig = 0;

// 15.11.75 nested component-build profiler. These hooks sit on helper entries but
// record time only while pcl_h4_post_component_build_profile is actively forwarding
// the H4 component-build call on the seam owner thread. All helpers remain stock.
static volatile i64 g_h4_nested_install_status = 0;
static volatile i64 g_h4_nested_restore_status = 0;
static volatile i64 g_h4_nested_active = 0;
static volatile i64 g_h4_nested_stock_restored = 1;
static volatile i64 g_h4_component_build_depth = 0;
static volatile i64 g_h4_nested_grow_calls = 0, g_h4_nested_grow_ticks = 0;
static volatile i64 g_h4_nested_payload_a_calls = 0, g_h4_nested_payload_a_ticks = 0;
static volatile i64 g_h4_nested_payload_b_calls = 0, g_h4_nested_payload_b_ticks = 0;
static volatile i64 g_h4_nested_recalc_calls = 0, g_h4_nested_recalc_ticks = 0;
static volatile i64 g_h4_nested_update_calls = 0, g_h4_nested_update_ticks = 0;
static volatile i64 g_h4_nested_tail_calls = 0, g_h4_nested_tail_ticks = 0;

typedef u64 (PCL_MS_ABI *H4NestedGrowFn)(u64,u64,u64,void*,void*,void*);
typedef u64 (PCL_MS_ABI *H4NestedPairFn)(void*,void*);
typedef u64 (PCL_MS_ABI *H4NestedOneFn)(void*);
static H4NestedGrowFn g_h4_nested_grow_orig = 0;
static H4NestedPairFn g_h4_nested_payload_a_orig = 0;
static H4NestedPairFn g_h4_nested_payload_b_orig = 0;
static H4NestedOneFn g_h4_nested_recalc_orig = 0;
static H4NestedOneFn g_h4_nested_update_orig = 0;
static H4NestedOneFn g_h4_nested_tail_orig = 0;

PCL_ALIGN(64) static u8 g_h4_nested_grow_tramp[64];
PCL_ALIGN(64) static u8 g_h4_nested_payload_a_tramp[64];
PCL_ALIGN(64) static u8 g_h4_nested_payload_b_tramp[64];
PCL_ALIGN(64) static u8 g_h4_nested_recalc_tramp[64];
PCL_ALIGN(64) static u8 g_h4_nested_update_tramp[64];
PCL_ALIGN(64) static u8 g_h4_nested_tail_tramp[64];
static u8 g_h4_nested_grow_saved[16];
static u8 g_h4_nested_payload_a_saved[12];
static u8 g_h4_nested_payload_b_saved[12];
static u8 g_h4_nested_recalc_saved[19];
static u8 g_h4_nested_update_saved[12];
static u8 g_h4_nested_tail_saved[13];

// 15.11.77: the prior direct-helper profiler is retained in source but disabled at runtime;
// only a single TArray header read per update call is used for the cardinality probe.
static volatile i64 g_h4_update_depth = 0;
static volatile i64 g_h4_update_direct_depth = 0;
static volatile i64 g_h4_update_direct_install_status = 0;
static volatile i64 g_h4_update_direct_restore_status = 0;
static volatile i64 g_h4_update_direct_active = 0;
static volatile i64 g_h4_update_direct_stock_restored = 1;
static volatile i64 g_h4_ud_create_calls=0, g_h4_ud_create_ticks=0;
static volatile i64 g_h4_ud_array_a_calls=0, g_h4_ud_array_a_ticks=0;
static volatile i64 g_h4_ud_array_b_calls=0, g_h4_ud_array_b_ticks=0;
static volatile i64 g_h4_ud_payload_calls=0, g_h4_ud_payload_ticks=0;
static volatile i64 g_h4_ud_dispatch_calls=0, g_h4_ud_dispatch_ticks=0;
static volatile i64 g_h4_ud_post_calls=0, g_h4_ud_post_ticks=0;
static volatile i64 g_h4_ud_alloc_calls=0, g_h4_ud_alloc_ticks=0;
static volatile i64 g_h4_ud_assign_calls=0, g_h4_ud_assign_ticks=0;

// 15.11.77: low-overhead cardinality probe for the update helper's existing
// component array at +0x5E8 (Num at +0x5F0). The stock update walks that array
// and calls its release helper once per element before rebuilding component state.
// We read only the TArray Num before/after each stock update call; no per-element
// hooks are installed.
static volatile i64 g_h4_update_card_before_items = 0;
static volatile i64 g_h4_update_card_after_items = 0;
static volatile i64 g_h4_update_card_nonzero_calls = 0;
static volatile i64 g_h4_update_card_zero_calls = 0;
static volatile i64 g_h4_update_card_max_before = 0;
static volatile i64 g_h4_update_card_guard_fail = 0;

// 15.11.80 retains the safe 15.11.79 tail-jumpsite timer for comparison.
// The only additional behavior in this phase is data-only vtable slot timing.
static volatile i64 g_h4_ut_tail_calls=0, g_h4_ut_tail_ticks=0;
static volatile i64 g_h4_ut_pre_calls=0, g_h4_ut_pre_ticks=0;
static volatile i64 g_h4_ut_dirty_calls=0, g_h4_ut_dirty_ticks=0;
static volatile i64 g_h4_ut_dispatch_calls=0, g_h4_ut_dispatch_ticks=0;
static volatile i64 g_h4_ut_tail_site_active=0, g_h4_ut_tail_site_stock_restored=1;
static H4NestedOneFn g_h4_ut_tail_orig=0, g_h4_ut_pre_orig=0;
typedef u64 (PCL_MS_ABI *H4UpdatePairFn)(void*,u64);
static H4UpdatePairFn g_h4_ut_dirty_orig=0, g_h4_ut_dispatch_orig=0;
PCL_ALIGN(64) static u8 g_h4_ut_tail_tramp[64], g_h4_ut_pre_tramp[64], g_h4_ut_dirty_tramp[64], g_h4_ut_dispatch_tramp[64];
static u8 g_h4_ut_tail_saved[14], g_h4_ut_pre_saved[13], g_h4_ut_dirty_saved[17], g_h4_ut_dispatch_saved[19];


// 15.11.80: seam-scoped vtable-slot profiler for the two synchronous hot-path
// virtual calls inside update RVA 0x40119F0 (calls at 0x4011C5D/+0x2D0 and
// 0x4011C69/+0x2B0). We patch data pointers only; no callee code is modified.
static const u32 H4_VT_CAP = 16u;
struct H4VTableEntry {
    u64 vtable;
    u64 orig_2d0;
    u64 orig_2b0;
};
static H4VTableEntry g_h4_vt[H4_VT_CAP];
static volatile i64 g_h4_vt_count = 0;
static volatile i64 g_h4_vt_patched = 0;
static volatile i64 g_h4_vt_peak = 0;
static volatile i64 g_h4_vt_patch_fail = 0;
static volatile i64 g_h4_vt_restore_fail = 0;
static volatile i64 g_h4_vt_guard_fail = 0;
static volatile i64 g_h4_v2d0_calls = 0, g_h4_v2d0_ticks = 0;
static volatile i64 g_h4_v2b0_calls = 0, g_h4_v2b0_ticks = 0;

// 15.11.88: measurement-only capture of the ORIGINAL vtable targets before
// the existing seam-scoped profiler swaps +0x2D0/+0x2B0. No additional
// detours or hot-path instructions are installed. These values let Lua report
// the exact game RVA and a 16-byte fingerprint for offline disassembly.
static volatile u64 g_h4_vt_first = 0;
static volatile u64 g_h4_vt_first_rva = 0;
static volatile u64 g_h4_v2d0_target = 0;
static volatile u64 g_h4_v2d0_target_rva = 0;
static volatile u64 g_h4_v2b0_target = 0;
static volatile u64 g_h4_v2b0_target_rva = 0;
static volatile i64 g_h4_v2b0_target_in_image = 0;
static volatile u32 g_h4_v2b0_sig0 = 0, g_h4_v2b0_sig1 = 0;
static volatile u32 g_h4_v2b0_sig2 = 0, g_h4_v2b0_sig3 = 0;
static volatile i64 g_h4_vt_capture_count = 0;
static volatile i64 g_h4_v2b0_target_mismatch = 0;

// 15.11.88: no-new-detour structure probe for the identified +0x2B0 target.
// The target itself begins by testing bits 0x09 at this+0xD9 and returns early
// when already processed. We classify expensive/early-return calls and sample
// the target's own 0x100-byte entry array without changing game behavior.
static volatile i64 g_h4_v2b0_heavy_calls = 0, g_h4_v2b0_heavy_ticks = 0;
static volatile i64 g_h4_v2b0_early_calls = 0, g_h4_v2b0_early_ticks = 0;
static volatile i64 g_h4_v2b0_heavy_entries = 0;
static volatile i64 g_h4_v2b0_heavy_entry_max = 0;
static volatile i64 g_h4_v2b0_zero_inner_entries = 0;
static volatile i64 g_h4_v2b0_subcount_total = 0;
static volatile i64 g_h4_v2b0_subcount_max = 0;
static volatile i64 g_h4_v2b0_ptr310_nonzero = 0;
static volatile i64 g_h4_v2b0_structure_guard_fail = 0;
typedef u64 (PCL_MS_ABI *H4VFuncOneFn)(void*);
static bool h4_vtable_ensure_for_component(u64 component);
static bool h4_vtable_restore_all();

typedef u64 (PCL_MS_ABI *H4UpdateAny6Fn)(u64,u64,u64,u64,u64,u64);

// 15.11.88: seam-scoped first-level child timing inside the heavy +0x2B0 target
// (RVA 0x3B9F4A0). Only helpers with relocation-safe copied prologues are
// detoured. Helpers with RIP-relative/conditional control flow in their first
// patch window (notably 0x3BA5A10 and 0x3BAE450) remain untouched.
static volatile i64 g_h4_v2b0_heavy_context = 0;
static volatile i64 g_h4_v2b0_child_depth = 0;
static volatile i64 g_h4_v2b0_child_install_status = 0;
static volatile i64 g_h4_v2b0_child_restore_status = 0;
static volatile i64 g_h4_v2b0_child_active = 0;
static volatile i64 g_h4_v2b0_child_stock_restored = 1;
static volatile i64 g_h4_v2b0_child_guard_fail = 0;

#define H4_V2B0_CHILD_COUNTERS(TAG) \
    static volatile i64 g_h4_v2b0_##TAG##_calls = 0; \
    static volatile i64 g_h4_v2b0_##TAG##_ticks = 0;
H4_V2B0_CHILD_COUNTERS(r3ba29a0)
H4_V2B0_CHILD_COUNTERS(r3b87e20)
H4_V2B0_CHILD_COUNTERS(r3b8ade0)
H4_V2B0_CHILD_COUNTERS(r3b895c0)
H4_V2B0_CHILD_COUNTERS(r3b9bab0)
H4_V2B0_CHILD_COUNTERS(r3ba2790)
H4_V2B0_CHILD_COUNTERS(r3b8b430)
H4_V2B0_CHILD_COUNTERS(r13ef490)
H4_V2B0_CHILD_COUNTERS(r3b9a3d0)
#undef H4_V2B0_CHILD_COUNTERS

static H4UpdateAny6Fn g_h4_v2b0_r3ba29a0_orig=0, g_h4_v2b0_r3b87e20_orig=0, g_h4_v2b0_r3b8ade0_orig=0;
static H4UpdateAny6Fn g_h4_v2b0_r3b895c0_orig=0, g_h4_v2b0_r3b9bab0_orig=0, g_h4_v2b0_r3ba2790_orig=0;
static H4UpdateAny6Fn g_h4_v2b0_r3b8b430_orig=0, g_h4_v2b0_r13ef490_orig=0, g_h4_v2b0_r3b9a3d0_orig=0;
PCL_ALIGN(64) static u8 g_h4_v2b0_r3ba29a0_tramp[64], g_h4_v2b0_r3b87e20_tramp[64], g_h4_v2b0_r3b8ade0_tramp[64];
PCL_ALIGN(64) static u8 g_h4_v2b0_r3b895c0_tramp[64], g_h4_v2b0_r3b9bab0_tramp[64], g_h4_v2b0_r3ba2790_tramp[64];
PCL_ALIGN(64) static u8 g_h4_v2b0_r3b8b430_tramp[64], g_h4_v2b0_r13ef490_tramp[64], g_h4_v2b0_r3b9a3d0_tramp[64];
static u8 g_h4_v2b0_r3ba29a0_saved[18], g_h4_v2b0_r3b87e20_saved[15], g_h4_v2b0_r3b8ade0_saved[13];
static u8 g_h4_v2b0_r3b895c0_saved[12], g_h4_v2b0_r3b9bab0_saved[13], g_h4_v2b0_r3ba2790_saved[15];
static u8 g_h4_v2b0_r3b8b430_saved[13], g_h4_v2b0_r13ef490_saved[13], g_h4_v2b0_r3b9a3d0_saved[15];

// 15.11.89: second-level timing inside first-level hotspot RVA 0x3B9BAB0.
// Profiling is armed only while the profiled 0x3B9BAB0 wrapper is executing,
// so shared helpers (especially 0x10D1A90) are not counted outside this path.
static volatile i64 g_h4_bab0_context = 0;
static volatile i64 g_h4_bab0_child_depth = 0;
static volatile i64 g_h4_bab0_child_install_status = 0;
static volatile i64 g_h4_bab0_child_restore_status = 0;
static volatile i64 g_h4_bab0_child_active = 0;
static volatile i64 g_h4_bab0_child_stock_restored = 1;
static volatile i64 g_h4_bab0_child_guard_fail = 0;
#define H4_BAB0_CHILD_COUNTERS(TAG) \
    static volatile i64 g_h4_bab0_##TAG##_calls = 0; \
    static volatile i64 g_h4_bab0_##TAG##_ticks = 0;
H4_BAB0_CHILD_COUNTERS(r3b8c990)
H4_BAB0_CHILD_COUNTERS(r3b98d20)
H4_BAB0_CHILD_COUNTERS(r3ba15b0)
H4_BAB0_CHILD_COUNTERS(r10d1a90)
#undef H4_BAB0_CHILD_COUNTERS
static H4UpdateAny6Fn g_h4_bab0_r3b8c990_orig=0, g_h4_bab0_r3b98d20_orig=0;
static H4UpdateAny6Fn g_h4_bab0_r3ba15b0_orig=0, g_h4_bab0_r10d1a90_orig=0;
PCL_ALIGN(64) static u8 g_h4_bab0_r3b8c990_tramp[64], g_h4_bab0_r3b98d20_tramp[64];
PCL_ALIGN(64) static u8 g_h4_bab0_r3ba15b0_tramp[64], g_h4_bab0_r10d1a90_tramp[64];
static u8 g_h4_bab0_r3b8c990_saved[15], g_h4_bab0_r3b98d20_saved[13];
static u8 g_h4_bab0_r3ba15b0_saved[14], g_h4_bab0_r10d1a90_saved[20];

// 15.11.90: third-level timing inside hotspot RVA 0x3B98D20.
// This measures the major relocation-safe direct children involved in
// temp index-array growth/setup and the <65535 / >=65535 final build split.
static volatile i64 g_h4_d20_context = 0;
static volatile i64 g_h4_d20_child_depth = 0;
static volatile i64 g_h4_d20_child_install_status = 0;
static volatile i64 g_h4_d20_child_restore_status = 0;
static volatile i64 g_h4_d20_child_active = 0;
static volatile i64 g_h4_d20_child_stock_restored = 1;
static volatile i64 g_h4_d20_child_guard_fail = 0;

// 15.11.96: corrected low-overhead A20 four-output stability qualification. Hosted
// inside the existing 0x3B99A20 wrapper from 15.11.90, so it adds no detour.
static const u32 H4_A20_PROOF_MATCHES = 8u;
static const u32 H4_A20_CANARY_INTERVAL = 128u;
static volatile i64 g_h4_a20_checks = 0;
static volatile i64 g_h4_a20_hash_ticks = 0;
static volatile i64 g_h4_a20_guard_fail = 0;
static volatile i64 g_h4_a20_promoted_sources = 0;
static volatile i64 g_h4_a20_rejected_sources = 0;
static volatile i64 g_h4_a20_late_demotions = 0;
static volatile i64 g_h4_a20_canary_calls = 0;
static volatile i64 g_h4_a20_canary_mismatch = 0;
static volatile i64 g_h4_a20_candidate_calls = 0, g_h4_a20_candidate_ticks = 0;
static volatile i64 g_h4_a20_proving_calls = 0, g_h4_a20_proving_ticks = 0;
static volatile i64 g_h4_a20_blocked_calls = 0, g_h4_a20_blocked_ticks = 0;
static volatile i64 g_h4_a20_output0_bytes = 0, g_h4_a20_output1_bytes = 0, g_h4_a20_output2_bytes = 0, g_h4_a20_output3_bytes = 0;
static volatile u64 g_h4_a20_first_mismatch_source = 0;
static volatile u32 g_h4_a20_first_mismatch_code = 0;

// 15.11.98: bounded cache for the four POD output arrays produced by 0x3B99A20.
// No game allocation is shared: cached bytes live in this DLL; each destination TArray
// remains game-owned and is resized through the same stock helper A20 uses.
static const u64 H4_A20_CACHE_CAP = 16ull * 1024ull * 1024ull;
PCL_ALIGN(64) static u8 g_h4_a20_cache[H4_A20_CACHE_CAP];
static volatile u64 g_h4_a20_cache_used = 0;
static volatile i64 g_h4_a20_cache_promoted_sources = 0;
static volatile i64 g_h4_a20_cache_arena_rejects = 0;
static volatile i64 g_h4_a20_cache_fast_calls = 0;
static volatile i64 g_h4_a20_cache_fast_bytes = 0;
static volatile i64 g_h4_a20_cache_copy_ticks = 0;
static volatile i64 g_h4_a20_cache_fallback_calls = 0;
static volatile i64 g_h4_a20_cache_apply_fail = 0;
static volatile i64 g_h4_a20_cache_resize_calls = 0;
static volatile i64 g_h4_a20_cache_resize_guard_ok = 0;
typedef void (PCL_MS_ABI *H4A20ResizeFn)(u32,u32,u32,u32,u64,u32,u64);
static H4A20ResizeFn g_h4_a20_resize = 0;

#define H4_D20_CHILD_COUNTERS(TAG) \
    static volatile i64 g_h4_d20_##TAG##_calls = 0; \
    static volatile i64 g_h4_d20_##TAG##_ticks = 0;
H4_D20_CHILD_COUNTERS(r10d0f20)
H4_D20_CHILD_COUNTERS(r3b99a20)
H4_D20_CHILD_COUNTERS(r1a297f0)
H4_D20_CHILD_COUNTERS(r3b7acf0)
H4_D20_CHILD_COUNTERS(r3b7b3a0)
#undef H4_D20_CHILD_COUNTERS
static H4UpdateAny6Fn g_h4_d20_r10d0f20_orig=0, g_h4_d20_r3b99a20_orig=0, g_h4_d20_r1a297f0_orig=0;
static H4UpdateAny6Fn g_h4_d20_r3b7acf0_orig=0, g_h4_d20_r3b7b3a0_orig=0;
PCL_ALIGN(64) static u8 g_h4_d20_r10d0f20_tramp[64], g_h4_d20_r3b99a20_tramp[64], g_h4_d20_r1a297f0_tramp[64];
PCL_ALIGN(64) static u8 g_h4_d20_r3b7acf0_tramp[64], g_h4_d20_r3b7b3a0_tramp[64];
static u8 g_h4_d20_r10d0f20_saved[19], g_h4_d20_r3b99a20_saved[17], g_h4_d20_r1a297f0_saved[20];
static u8 g_h4_d20_r3b7acf0_saved[16], g_h4_d20_r3b7b3a0_saved[16];

// 15.11.100: safe single-entry qualification at 0x1CFF490 only.
// The deeper 0x1C03CE0 / 0x1D361F0 child detours from 15.11.92 remain disabled.
static volatile i64 g_h4_acf0_context = 0;
static volatile i64 g_h4_f490_depth = 0;
static volatile i64 g_h4_f490_install_status = 0;
static volatile i64 g_h4_f490_restore_status = 0;
static volatile i64 g_h4_f490_active = 0;
static volatile i64 g_h4_f490_stock_restored = 1;
static volatile i64 g_h4_f490_calls = 0;
static volatile i64 g_h4_f490_ticks = 0;
static volatile i64 g_h4_f490_checks = 0;
static volatile i64 g_h4_f490_hash_ticks = 0;
static volatile i64 g_h4_f490_guard_fail = 0;
static volatile i64 g_h4_f490_promoted_sources = 0;
static volatile i64 g_h4_f490_rejected_sources = 0;
static volatile i64 g_h4_f490_late_demotions = 0;
static volatile i64 g_h4_f490_canary_calls = 0;
static volatile i64 g_h4_f490_canary_mismatch = 0;
static volatile i64 g_h4_f490_candidate_calls = 0, g_h4_f490_candidate_ticks = 0;
static volatile i64 g_h4_f490_proving_calls = 0, g_h4_f490_proving_ticks = 0;
static volatile i64 g_h4_f490_blocked_calls = 0, g_h4_f490_blocked_ticks = 0;
static volatile u64 g_h4_f490_first_mismatch_source = 0;
static volatile u32 g_h4_f490_first_mismatch_code = 0;
static const u32 H4_F490_PROOF_MATCHES = 8u;
static const u32 H4_F490_CANARY_INTERVAL = 128u;
static H4UpdateAny6Fn g_h4_f490_orig = 0;
PCL_ALIGN(64) static u8 g_h4_f490_tramp[64];
static u8 g_h4_f490_saved[13];

// 15.11.100: seam-scoped mid-function bypass at F490+0x159 (RVA 0x1CFF5E9).
// At this point all stock ownership/setup is complete. Fast path writes only the proven
// 48-byte bounds at object+0x88 and jumps to the untouched stock finalizer at 0x1CFF98C.
static H4SourceEntry* g_h4_f490_fast_entry = 0;
static volatile u64 g_h4_f490_fast_object = 0;
static volatile i64 g_h4_f490_fast_calls = 0;
static volatile i64 g_h4_f490_fast_bytes = 0;
static volatile i64 g_h4_f490_fast_copy_ticks = 0;
static volatile i64 g_h4_f490_fast_misses = 0;
static volatile i64 g_h4_f490_mid_guard_fail = 0;
static volatile i64 g_h4_f490_mid_install_status = 0;
static volatile i64 g_h4_f490_mid_restore_status = 0;
static volatile i64 g_h4_f490_mid_active = 0;
static volatile i64 g_h4_f490_mid_stock_restored = 1;
static volatile u64 g_h4_f490_mid_fast_cont = 0;
PCL_ALIGN(64) static u8 g_h4_f490_mid_tramp[64];
PCL_ALIGN(64) static u8 g_h4_f490_mid_dispatch[128];
static u8 g_h4_f490_mid_saved[16];

// 15.11.101: safe direct-callsite timing for F490's stock finalizer at RVA 0x1D361F0.
// We do not detour the finalizer entry. Instead we replace the 32-byte F490 tail beginning
// at RVA 0x1CFF98F with an absolute indirect CALL whose target qword lives in the function's
// own trailing INT3 padding, then execute the exact stock epilogue bytes.
typedef void (PCL_MS_ABI *H4F490FinalizerFn)(void*);
static H4F490FinalizerFn g_h4_f490_finalizer_orig = 0;
static volatile i64 g_h4_f490_finalizer_install_status = 0;
static volatile i64 g_h4_f490_finalizer_restore_status = 0;
static volatile i64 g_h4_f490_finalizer_active = 0;
static volatile i64 g_h4_f490_finalizer_stock_restored = 1;
static volatile i64 g_h4_f490_finalizer_calls = 0;
static volatile i64 g_h4_f490_finalizer_ticks = 0;
static volatile i64 g_h4_f490_finalizer_guard_fail = 0;
static u8 g_h4_f490_finalizer_saved[32];

// 15.11.103: direct-callsite split of the hot 0x1D361F0 finalizer tail.
// Patch RVA 0x1D363D0 covers exactly:
//   lea rdx,[rsp+0x50]; mov rcx,rdi; call 0x1D36420;
//   lea rcx,[rsp+0x50]; call 0x1D2FEB0
// The replacement reconstructs RCX/RDX and calls one ABI-known wrapper.
// Neither child entry is detoured.
typedef void (PCL_MS_ABI *H4F490TailBuildFn)(void*, void*);
typedef void (PCL_MS_ABI *H4F490TailCleanupFn)(void*);
static H4F490TailBuildFn g_h4_f490_tail_build_orig = 0;
static H4F490TailCleanupFn g_h4_f490_tail_cleanup_orig = 0;
static volatile i64 g_h4_f490_tail_install_status = 0;
static volatile i64 g_h4_f490_tail_restore_status = 0;
static volatile i64 g_h4_f490_tail_active = 0;
static volatile i64 g_h4_f490_tail_stock_restored = 1;
static volatile i64 g_h4_f490_tail_build_calls = 0;
static volatile i64 g_h4_f490_tail_build_ticks = 0;
static volatile i64 g_h4_f490_tail_cleanup_calls = 0;
static volatile i64 g_h4_f490_tail_cleanup_ticks = 0;
static volatile i64 g_h4_f490_tail_guard_fail = 0;
static u8 g_h4_f490_tail_saved[23];

static H4UpdateAny6Fn g_h4_ud_create_orig=0, g_h4_ud_array_a_orig=0, g_h4_ud_array_b_orig=0, g_h4_ud_payload_orig=0;
static H4UpdateAny6Fn g_h4_ud_dispatch_orig=0, g_h4_ud_post_orig=0, g_h4_ud_alloc_orig=0, g_h4_ud_assign_orig=0;
PCL_ALIGN(64) static u8 g_h4_ud_create_tramp[64], g_h4_ud_array_a_tramp[64], g_h4_ud_array_b_tramp[64], g_h4_ud_payload_tramp[64];
PCL_ALIGN(64) static u8 g_h4_ud_dispatch_tramp[64], g_h4_ud_post_tramp[64], g_h4_ud_alloc_tramp[64], g_h4_ud_assign_tramp[64];
static u8 g_h4_ud_create_saved[18], g_h4_ud_array_a_saved[19], g_h4_ud_array_b_saved[20], g_h4_ud_payload_saved[13];
static u8 g_h4_ud_dispatch_saved[19], g_h4_ud_post_saved[14], g_h4_ud_alloc_saved[13], g_h4_ud_assign_saved[12];

struct H4PayloadFingerprint {
    u64 bounds_hash;
    u64 index_hash;
    u64 vertex_hash;
    u32 index_num;
    u32 vertex_num;
    u64 index_bytes;
    u64 vertex_bytes;
};

static inline u64 h4_fnv1a_bytes(u64 p, u64 n, u64 seed) {
    u64 h = seed;
    for (u64 i = 0; i < n; ++i) {
        h ^= (u64)rd<u8>(p + i);
        h *= 1099511628211ull;
    }
    return h;
}

static bool h4_capture_payload(void* actor_ptr, H4PayloadFingerprint* out) {
    if (!actor_ptr || !out) return false;
    const u64 actor = (u64)actor_ptr;
    if (actor < 0x10000ull) return false;

    const i32 index_num = rd<i32>(actor + 0x4B0);
    const i32 index_max = rd<i32>(actor + 0x4B4);
    const i32 vertex_num = rd<i32>(actor + 0x4C0);
    const i32 vertex_max = rd<i32>(actor + 0x4C4);
    const u64 index_data = rd<u64>(actor + 0x4A8);
    const u64 vertex_data = rd<u64>(actor + 0x4B8);

    // Fail closed on implausible TArray headers. The caps are far above known
    // Bladesong part meshes but prevent a corrupt count from turning diagnostics
    // into an unbounded read.
    if (index_num < 0 || index_max < index_num || index_num > 10000000) return false;
    if (vertex_num < 0 || vertex_max < vertex_num || vertex_num > 2000000) return false;
    if (index_num > 0 && index_data < 0x10000ull) return false;
    if (vertex_num > 0 && vertex_data < 0x10000ull) return false;

    const u64 index_bytes = (u64)(u32)index_num * 4ull;
    const u64 vertex_bytes = (u64)(u32)vertex_num * 0x98ull;
    if (index_bytes > 0x10000000ull || vertex_bytes > 0x20000000ull) return false;

    const u64 basis = 1469598103934665603ull;
    out->bounds_hash = h4_fnv1a_bytes(actor + 0x470, 0x38, basis);
    out->index_hash = index_bytes ? h4_fnv1a_bytes(index_data, index_bytes, basis) : basis;
    out->vertex_hash = vertex_bytes ? h4_fnv1a_bytes(vertex_data, vertex_bytes, basis) : basis;
    out->index_num = (u32)index_num;
    out->vertex_num = (u32)vertex_num;
    out->index_bytes = index_bytes;
    out->vertex_bytes = vertex_bytes;
    return true;
}

static bool h4_capture_vertex_signature(void* actor_ptr, u64* out_hash, u32* out_num,
                                        u64* out_bytes, u64* out_data) {
    if (!actor_ptr) return false;
    const u64 actor = (u64)actor_ptr;
    if (actor < 0x10000ull) return false;

    const i32 vertex_num = rd<i32>(actor + 0x4C0);
    const i32 vertex_max = rd<i32>(actor + 0x4C4);
    const u64 vertex_data = rd<u64>(actor + 0x4B8);
    if (vertex_num < 0 || vertex_max < vertex_num || vertex_num > 2000000) return false;
    if (vertex_num > 0 && vertex_data < 0x10000ull) return false;
    const u64 bytes = (u64)(u32)vertex_num * 0x98ull;
    if (bytes > 0x20000000ull) return false;

    const u64 basis = 1469598103934665603ull;
    const u64 hash = bytes ? h4_fnv1a_bytes(vertex_data, bytes, basis) : basis;
    if (out_hash) *out_hash = hash;
    if (out_num) *out_num = (u32)vertex_num;
    if (out_bytes) *out_bytes = bytes;
    if (out_data) *out_data = vertex_data;
    return true;
}

static inline void h4_copy_bytes(u64 dst, u64 src, u64 n) {
    // Deliberately tiny no-CRT memcpy. Copy qwords first, then the tail.
    u64 i = 0;
    for (; i + 8ull <= n; i += 8ull) wr<u64>(dst + i, rd<u64>(src + i));
    for (; i < n; ++i) wr<u8>(dst + i, rd<u8>(src + i));
}

static bool h4_capture_tarray_stride(u64 arr, u32 stride, u64* out_hash, u32* out_num, u64* out_bytes) {
    if (arr < 0x10000ull || stride == 0u || stride > 0x1000u) return false;
    const u64 data = rd<u64>(arr + 0x0);
    const i32 num = rd<i32>(arr + 0x8);
    const i32 max = rd<i32>(arr + 0xC);
    if (num < 0 || max < num || num > 10000000) return false;
    if (num > 0 && data < 0x10000ull) return false;
    const u64 bytes = (u64)(u32)num * (u64)stride;
    if (bytes > 0x10000000ull) return false;
    const u64 basis = 1469598103934665603ull;
    const u64 hash = bytes ? h4_fnv1a_bytes(data, bytes, basis) : basis;
    if (out_hash) *out_hash = hash;
    if (out_num) *out_num = (u32)num;
    if (out_bytes) *out_bytes = bytes;
    return true;
}
static bool h4_capture_int_tarray(u64 arr, u64* out_hash, u32* out_num, u64* out_bytes) {
    return h4_capture_tarray_stride(arr, 4u, out_hash, out_num, out_bytes);
}


static inline u64 h4_align16(u64 v) { return (v + 15ull) & ~15ull; }

static bool h4_a20_target_header_ok(u64 arr) {
    if (arr < 0x10000ull) return false;
    const u64 data = rd<u64>(arr + 0x0);
    const i32 num = rd<i32>(arr + 0x8);
    const i32 max = rd<i32>(arr + 0xC);
    if (num < 0 || max < num || max < 0 || max > 10000000) return false;
    if (max > 0 && data < 0x10000ull) return false;
    return true;
}

static bool h4_a20_capture_cache(H4SourceEntry* e,
                                  u64 a1,u64 a2,u64 a3,u64 a4,
                                  u64 b0,u64 b1,u64 b2,u64 b3) {
    if (!e || e->a20_reserved == 1u) return e != 0;
    const u64 d0 = b0 ? rd<u64>(a1) : 0;
    const u64 d1 = b1 ? rd<u64>(a2) : 0;
    const u64 d2 = b2 ? rd<u64>(a3) : 0;
    const u64 d3 = b3 ? rd<u64>(a4) : 0;
    if ((b0 && d0 < 0x10000ull) || (b1 && d1 < 0x10000ull) ||
        (b2 && d2 < 0x10000ull) || (b3 && d3 < 0x10000ull)) return false;

    const u64 o0 = h4_align16(g_h4_a20_cache_used);
    const u64 o1 = h4_align16(o0 + b0);
    const u64 o2 = h4_align16(o1 + b1);
    const u64 o3 = h4_align16(o2 + b2);
    const u64 end = o3 + b3;
    if (o0 > H4_A20_CACHE_CAP || o1 > H4_A20_CACHE_CAP ||
        o2 > H4_A20_CACHE_CAP || o3 > H4_A20_CACHE_CAP || end > H4_A20_CACHE_CAP) {
        e->a20_reserved = 2u;
        g_h4_a20_cache_arena_rejects++;
        return false;
    }
    if (b0) h4_copy_bytes((u64)&g_h4_a20_cache[o0], d0, b0);
    if (b1) h4_copy_bytes((u64)&g_h4_a20_cache[o1], d1, b1);
    if (b2) h4_copy_bytes((u64)&g_h4_a20_cache[o2], d2, b2);
    if (b3) h4_copy_bytes((u64)&g_h4_a20_cache[o3], d3, b3);
    e->a20_cache_off0=o0; e->a20_cache_off1=o1; e->a20_cache_off2=o2; e->a20_cache_off3=o3;
    e->a20_cache_bytes0=b0; e->a20_cache_bytes1=b1; e->a20_cache_bytes2=b2; e->a20_cache_bytes3=b3;
    e->a20_reserved = 1u;
    g_h4_a20_cache_used = end;
    g_h4_a20_cache_promoted_sources++;
    return true;
}

static bool h4_a20_write_cached_array(u64 arr, u32 stride, u64 cache_off, u64 bytes, u32 num) {
    if (!h4_a20_target_header_ok(arr) || !g_h4_a20_resize) return false;
    if (cache_off > H4_A20_CACHE_CAP || bytes > H4_A20_CACHE_CAP || cache_off + bytes > H4_A20_CACHE_CAP) return false;
    if ((u64)num * (u64)stride != bytes) return false;
    const i32 old_max = rd<i32>(arr + 0xC);
    wr<i32>(arr + 0x8, (i32)num);
    // Stock 0x10D0AB0 only grows when desired capacity exceeds old Max. If the
    // existing destination allocation is already large enough, preserve it exactly
    // and avoid a needless helper call.
    if ((i32)num > old_max) {
        g_h4_a20_resize(stride, 4u, num, (u32)old_max, arr, num, arr + 0xC);
        g_h4_a20_cache_resize_calls++;
    }
    const i32 new_max = rd<i32>(arr + 0xC);
    const u64 data = rd<u64>(arr + 0x0);
    if (new_max < (i32)num || new_max < 0 || new_max > 10000000) return false;
    if (bytes > 0 && data < 0x10000ull) return false;
    if (bytes > 0) h4_copy_bytes(data, (u64)&g_h4_a20_cache[cache_off], bytes);
    return true;
}

static bool h4_a20_apply_cache(H4SourceEntry* e, u64 a1,u64 a2,u64 a3,u64 a4) {
    if (!e || e->a20_state != 2u || e->a20_reserved != 1u || !g_h4_a20_resize) return false;
    // Preflight all destination headers before mutating any of them.
    if (!h4_a20_target_header_ok(a1) || !h4_a20_target_header_ok(a2) ||
        !h4_a20_target_header_ok(a3) || !h4_a20_target_header_ok(a4)) return false;
    if (!h4_a20_write_cached_array(a1,12u,e->a20_cache_off0,e->a20_cache_bytes0,e->a20_num0)) return false;
    if (!h4_a20_write_cached_array(a2, 4u,e->a20_cache_off1,e->a20_cache_bytes1,e->a20_num1)) return false;
    if (!h4_a20_write_cached_array(a3, 4u,e->a20_cache_off2,e->a20_cache_bytes2,e->a20_num2)) return false;
    if (!h4_a20_write_cached_array(a4, 4u,e->a20_cache_off3,e->a20_cache_bytes3,e->a20_num3)) return false;
    return true;
}

static inline u32 h4_source_hash(u64 p) {
    p ^= p >> 33;
    p *= 0xff51afd7ed558ccdull;
    p ^= p >> 33;
    return (u32)p & (H4_SOURCE_CAP - 1u);
}

static H4SourceEntry* h4_source_slot(u64 source, bool* first) {
    if (first) *first = false;
    if (!source) return 0;
    u32 idx = h4_source_hash(source);
    for (u32 n = 0; n < H4_SOURCE_CAP; ++n) {
        H4SourceEntry* e = &g_h4_sources[(idx + n) & (H4_SOURCE_CAP - 1u)];
        if (e->source == source) return e;
        if (e->source == 0) {
            e->source = source;
            e->ticks = 0;
            e->calls = 0;
            e->fp_state = 0;
            e->geometry_state = 0;
            e->reserved = 0;
            e->bounds_hash = 0;
            e->index_hash = 0;
            e->vertex_hash = 0;
            e->index_num = 0;
            e->vertex_num = 0;
            e->proof_vertex_hash = 0;
            e->cache_offset = 0;
            e->cache_bytes = 0;
            e->proof_vertex_num = 0;
            e->proof_matches = 0;
            e->cache_state = 0;
            e->fast_since_canary = 0;
            e->a20_hash0 = 0;
            e->a20_hash1 = 0;
            e->a20_hash2 = 0;
            e->a20_hash3 = 0;
            e->a20_num0 = 0;
            e->a20_num1 = 0;
            e->a20_num2 = 0;
            e->a20_num3 = 0;
            e->a20_state = 0;
            e->a20_matches = 0;
            e->a20_since_canary = 0;
            e->a20_reserved = 0;
            e->a20_cache_off0 = e->a20_cache_off1 = e->a20_cache_off2 = e->a20_cache_off3 = 0;
            e->a20_cache_bytes0 = e->a20_cache_bytes1 = e->a20_cache_bytes2 = e->a20_cache_bytes3 = 0;
            e->f490_bounds_hash = 0;
            for (u32 j=0;j<6u;++j) e->f490_bounds_cache[j] = 0;
            e->f490_state = 0; e->f490_matches = 0; e->f490_since_canary = 0; e->f490_reserved = 0;
            g_h4_unique_sources++;
            if (first) *first = true;
            return e;
        }
    }
    g_h4_table_overflow++;
    return 0;
}

static void h4_profile_reset() {
    g_h4_scope_calls = 0;
    g_h4_profile_calls = 0;
    g_h4_other_thread_calls = 0;
    g_h4_unique_sources = 0;
    g_h4_repeat_calls = 0;
    g_h4_first_ticks = 0;
    g_h4_repeat_ticks = 0;
    g_h4_total_ticks = 0;
    g_h4_null_source_calls = 0;
    g_h4_table_overflow = 0;
    g_h4_max_calls_per_source = 0;
    g_h4_max_source_ptr = 0;
    g_h4_max_source_ticks = 0;
    g_h4_hot_source_ptr = 0;
    g_h4_hot_source_calls = 0;
    g_h4_hot_source_ticks = 0;
    g_h4_fp_sources_captured = 0;
    g_h4_fp_sources_validated = 0;
    g_h4_fp_sources_mismatch = 0;
    g_h4_fp_guard_fail = 0;
    g_h4_fp_checks = 0;
    g_h4_fp_hash_ticks = 0;
    g_h4_fp_index_bytes = 0;
    g_h4_fp_vertex_bytes = 0;
    g_h4_fp_first_mismatch_source = 0;
    g_h4_fp_first_mismatch_code = 0;
    g_h4_fp_geometry_validated = 0;
    g_h4_fp_geometry_mismatch = 0;
    g_h4_fp_bounds_only_mismatch = 0;
    g_h4_fp_bounds_mismatch = 0;
    g_h4_fp_index_num_mismatch = 0;
    g_h4_fp_vertex_num_mismatch = 0;
    g_h4_fp_index_hash_mismatch = 0;
    g_h4_fp_vertex_hash_mismatch = 0;
    g_h4_fp_first_geometry_mismatch_source = 0;
    g_h4_fp_first_geometry_mismatch_code = 0;
    g_h4_stable_post_calls = 0;
    g_h4_stable_post_ticks = 0;
    g_h4_unstable_post_calls = 0;
    g_h4_unstable_post_ticks = 0;
    g_h4_unresolved_repeat_calls = 0;
    g_h4_unresolved_repeat_ticks = 0;

    g_h4_vertex_cache_used = 0;
    g_h4_current_fast_entry = 0;
    g_h4_current_fast_used = 0;
    g_h4_current_scope_entry = 0;
    g_h4_cache_promoted_sources = 0;
    g_h4_cache_rejected_sources = 0;
    g_h4_cache_late_demotions = 0;
    g_h4_cache_fast_calls = 0;
    g_h4_cache_fast_bytes = 0;
    g_h4_cache_copy_ticks = 0;
    g_h4_cache_mid_guard_fail = 0;
    g_h4_cache_canary_calls = 0;
    g_h4_cache_canary_mismatch = 0;
    g_h4_cache_proof_checks = 0;
    g_h4_cache_proof_ticks = 0;
    g_h4_cache_arena_rejects = 0;
    g_h4_post_vertex_copy_calls = 0;
    g_h4_post_vertex_copy_ticks = 0;
    g_h4_post_index_copy_calls = 0;
    g_h4_post_index_copy_ticks = 0;
    g_h4_post_component_build_calls = 0;
    g_h4_post_component_build_ticks = 0;
    g_h4_post_component_final_calls = 0;
    g_h4_post_component_final_ticks = 0;
    g_h4_component_build_depth = 0;
    g_h4_nested_grow_calls = g_h4_nested_grow_ticks = 0;
    g_h4_nested_payload_a_calls = g_h4_nested_payload_a_ticks = 0;
    g_h4_nested_payload_b_calls = g_h4_nested_payload_b_ticks = 0;
    g_h4_nested_recalc_calls = g_h4_nested_recalc_ticks = 0;
    g_h4_nested_update_calls = g_h4_nested_update_ticks = 0;
    g_h4_nested_tail_calls = g_h4_nested_tail_ticks = 0;
    g_h4_update_depth = 0;
    g_h4_update_direct_depth = 0;
    g_h4_ud_create_calls = g_h4_ud_create_ticks = 0;
    g_h4_ud_array_a_calls = g_h4_ud_array_a_ticks = 0;
    g_h4_ud_array_b_calls = g_h4_ud_array_b_ticks = 0;
    g_h4_ud_payload_calls = g_h4_ud_payload_ticks = 0;
    g_h4_ud_dispatch_calls = g_h4_ud_dispatch_ticks = 0;
    g_h4_ud_post_calls = g_h4_ud_post_ticks = 0;
    g_h4_ud_alloc_calls = g_h4_ud_alloc_ticks = 0;
    g_h4_ud_assign_calls = g_h4_ud_assign_ticks = 0;
    g_h4_update_card_before_items = 0;
    g_h4_update_card_after_items = 0;
    g_h4_update_card_nonzero_calls = 0;
    g_h4_update_card_zero_calls = 0;
    g_h4_update_card_max_before = 0;
    g_h4_update_card_guard_fail = 0;
    g_h4_ut_tail_calls = g_h4_ut_tail_ticks = 0;
    g_h4_ut_pre_calls = g_h4_ut_pre_ticks = 0;
    g_h4_ut_dirty_calls = g_h4_ut_dirty_ticks = 0;
    g_h4_ut_dispatch_calls = g_h4_ut_dispatch_ticks = 0;
    g_h4_vt_patched = 0;
    g_h4_vt_peak = 0;
    g_h4_vt_patch_fail = 0;
    g_h4_vt_restore_fail = 0;
    g_h4_vt_guard_fail = 0;
    g_h4_v2d0_calls = g_h4_v2d0_ticks = 0;
    g_h4_v2b0_calls = g_h4_v2b0_ticks = 0;
    g_h4_vt_first = 0;
    g_h4_vt_first_rva = 0;
    g_h4_v2d0_target = 0;
    g_h4_v2d0_target_rva = 0;
    g_h4_v2b0_target = 0;
    g_h4_v2b0_target_rva = 0;
    g_h4_v2b0_target_in_image = 0;
    g_h4_v2b0_sig0 = g_h4_v2b0_sig1 = 0;
    g_h4_v2b0_sig2 = g_h4_v2b0_sig3 = 0;
    g_h4_vt_capture_count = 0;
    g_h4_v2b0_target_mismatch = 0;
    g_h4_v2b0_heavy_calls = g_h4_v2b0_heavy_ticks = 0;
    g_h4_v2b0_early_calls = g_h4_v2b0_early_ticks = 0;
    g_h4_v2b0_heavy_entries = 0;
    g_h4_v2b0_heavy_entry_max = 0;
    g_h4_v2b0_zero_inner_entries = 0;
    g_h4_v2b0_subcount_total = 0;
    g_h4_v2b0_subcount_max = 0;
    g_h4_v2b0_ptr310_nonzero = 0;
    g_h4_v2b0_structure_guard_fail = 0;
    g_h4_v2b0_heavy_context = 0;
    g_h4_v2b0_child_depth = 0;
    g_h4_v2b0_child_guard_fail = 0;
    g_h4_v2b0_r3ba29a0_calls = g_h4_v2b0_r3ba29a0_ticks = 0;
    g_h4_v2b0_r3b87e20_calls = g_h4_v2b0_r3b87e20_ticks = 0;
    g_h4_v2b0_r3b8ade0_calls = g_h4_v2b0_r3b8ade0_ticks = 0;
    g_h4_v2b0_r3b895c0_calls = g_h4_v2b0_r3b895c0_ticks = 0;
    g_h4_v2b0_r3b9bab0_calls = g_h4_v2b0_r3b9bab0_ticks = 0;
    g_h4_v2b0_r3ba2790_calls = g_h4_v2b0_r3ba2790_ticks = 0;
    g_h4_v2b0_r3b8b430_calls = g_h4_v2b0_r3b8b430_ticks = 0;
    g_h4_v2b0_r13ef490_calls = g_h4_v2b0_r13ef490_ticks = 0;
    g_h4_v2b0_r3b9a3d0_calls = g_h4_v2b0_r3b9a3d0_ticks = 0;
    g_h4_bab0_context = 0;
    g_h4_bab0_child_depth = 0;
    g_h4_bab0_child_guard_fail = 0;
    g_h4_bab0_r3b8c990_calls = g_h4_bab0_r3b8c990_ticks = 0;
    g_h4_bab0_r3b98d20_calls = g_h4_bab0_r3b98d20_ticks = 0;
    g_h4_bab0_r3ba15b0_calls = g_h4_bab0_r3ba15b0_ticks = 0;
    g_h4_bab0_r10d1a90_calls = g_h4_bab0_r10d1a90_ticks = 0;
    g_h4_d20_context = 0;
    g_h4_d20_child_depth = 0;
    g_h4_d20_child_guard_fail = 0;
    g_h4_d20_r10d0f20_calls = g_h4_d20_r10d0f20_ticks = 0;
    g_h4_d20_r3b99a20_calls = g_h4_d20_r3b99a20_ticks = 0;
    g_h4_d20_r1a297f0_calls = g_h4_d20_r1a297f0_ticks = 0;
    g_h4_d20_r3b7acf0_calls = g_h4_d20_r3b7acf0_ticks = 0;
    g_h4_d20_r3b7b3a0_calls = g_h4_d20_r3b7b3a0_ticks = 0;
    g_h4_a20_checks = g_h4_a20_hash_ticks = g_h4_a20_guard_fail = 0;
    g_h4_a20_promoted_sources = g_h4_a20_rejected_sources = 0;
    g_h4_a20_late_demotions = g_h4_a20_canary_calls = g_h4_a20_canary_mismatch = 0;
    g_h4_a20_candidate_calls = g_h4_a20_candidate_ticks = 0;
    g_h4_a20_proving_calls = g_h4_a20_proving_ticks = 0;
    g_h4_a20_blocked_calls = g_h4_a20_blocked_ticks = 0;
    g_h4_a20_output0_bytes = g_h4_a20_output1_bytes = g_h4_a20_output2_bytes = g_h4_a20_output3_bytes = 0;
    g_h4_a20_first_mismatch_source = 0;
    g_h4_a20_first_mismatch_code = 0;
    g_h4_a20_cache_used = 0;
    g_h4_a20_cache_promoted_sources = 0;
    g_h4_a20_cache_arena_rejects = 0;
    g_h4_a20_cache_fast_calls = 0;
    g_h4_a20_cache_fast_bytes = 0;
    g_h4_a20_cache_copy_ticks = 0;
    g_h4_a20_cache_fallback_calls = 0;
    g_h4_a20_cache_apply_fail = 0;
    g_h4_a20_cache_resize_calls = 0;
    g_h4_acf0_context = 0;
    g_h4_f490_depth = 0;
    g_h4_f490_calls = g_h4_f490_ticks = 0;
    g_h4_f490_checks = g_h4_f490_hash_ticks = g_h4_f490_guard_fail = 0;
    g_h4_f490_promoted_sources = g_h4_f490_rejected_sources = 0;
    g_h4_f490_late_demotions = g_h4_f490_canary_calls = g_h4_f490_canary_mismatch = 0;
    g_h4_f490_candidate_calls = g_h4_f490_candidate_ticks = 0;
    g_h4_f490_proving_calls = g_h4_f490_proving_ticks = 0;
    g_h4_f490_blocked_calls = g_h4_f490_blocked_ticks = 0;
    g_h4_f490_first_mismatch_source = 0;
    g_h4_f490_first_mismatch_code = 0;
    g_h4_f490_fast_entry = 0;
    g_h4_f490_fast_object = 0;
    g_h4_f490_fast_calls = 0;
    g_h4_f490_fast_bytes = 0;
    g_h4_f490_fast_copy_ticks = 0;
    g_h4_f490_fast_misses = 0;
    g_h4_f490_mid_guard_fail = 0;
    g_h4_f490_finalizer_calls = 0;
    g_h4_f490_finalizer_ticks = 0;
    g_h4_f490_finalizer_guard_fail = 0;
    g_h4_f490_tail_build_calls = 0;
    g_h4_f490_tail_build_ticks = 0;
    g_h4_f490_tail_cleanup_calls = 0;
    g_h4_f490_tail_cleanup_ticks = 0;
    g_h4_f490_tail_guard_fail = 0;
    for (u32 i = 0; i < H4_SOURCE_CAP; ++i) {
        g_h4_sources[i].source = 0;
        g_h4_sources[i].ticks = 0;
        g_h4_sources[i].calls = 0;
        g_h4_sources[i].fp_state = 0;
        g_h4_sources[i].geometry_state = 0;
        g_h4_sources[i].reserved = 0;
        g_h4_sources[i].bounds_hash = 0;
        g_h4_sources[i].index_hash = 0;
        g_h4_sources[i].vertex_hash = 0;
        g_h4_sources[i].index_num = 0;
        g_h4_sources[i].vertex_num = 0;
        g_h4_sources[i].proof_vertex_hash = 0;
        g_h4_sources[i].cache_offset = 0;
        g_h4_sources[i].cache_bytes = 0;
        g_h4_sources[i].proof_vertex_num = 0;
        g_h4_sources[i].proof_matches = 0;
        g_h4_sources[i].cache_state = 0;
        g_h4_sources[i].fast_since_canary = 0;
        g_h4_sources[i].a20_hash0 = 0;
        g_h4_sources[i].a20_hash1 = 0;
        g_h4_sources[i].a20_hash2 = 0;
        g_h4_sources[i].a20_hash3 = 0;
        g_h4_sources[i].a20_num0 = 0;
        g_h4_sources[i].a20_num1 = 0;
        g_h4_sources[i].a20_num2 = 0;
        g_h4_sources[i].a20_num3 = 0;
        g_h4_sources[i].a20_state = 0;
        g_h4_sources[i].a20_matches = 0;
        g_h4_sources[i].a20_since_canary = 0;
        g_h4_sources[i].a20_reserved = 0;
        g_h4_sources[i].a20_cache_off0 = g_h4_sources[i].a20_cache_off1 = 0;
        g_h4_sources[i].a20_cache_off2 = g_h4_sources[i].a20_cache_off3 = 0;
        g_h4_sources[i].a20_cache_bytes0 = g_h4_sources[i].a20_cache_bytes1 = 0;
        g_h4_sources[i].a20_cache_bytes2 = g_h4_sources[i].a20_cache_bytes3 = 0;
        g_h4_sources[i].f490_bounds_hash = 0;
        for (u32 j=0;j<6u;++j) g_h4_sources[i].f490_bounds_cache[j] = 0;
        g_h4_sources[i].f490_state = 0;
        g_h4_sources[i].f490_matches = 0;
        g_h4_sources[i].f490_since_canary = 0;
        g_h4_sources[i].f490_reserved = 0;
    }
}

extern "C" int PCL_MS_ABI
h4_mid_try_fast(void* actor_ptr) {
    H4SourceEntry* e = g_h4_current_fast_entry;
    if (!e || e->cache_state != 2u || !actor_ptr) return 0;

    const u64 actor = (u64)actor_ptr;
    if (actor < 0x10000ull ||
        e->cache_offset > H4_VERTEX_CACHE_CAP ||
        e->cache_bytes > H4_VERTEX_CACHE_CAP ||
        e->cache_offset + e->cache_bytes > H4_VERTEX_CACHE_CAP) {
        g_h4_cache_mid_guard_fail++;
        return 0;
    }

    const i32 vertex_num = rd<i32>(actor + 0x4C0);
    const i32 vertex_max = rd<i32>(actor + 0x4C4);
    const u64 vertex_data = rd<u64>(actor + 0x4B8);
    if (vertex_num < 0 || vertex_max < vertex_num ||
        (u32)vertex_num != e->proof_vertex_num ||
        (u64)(u32)vertex_num * 0x98ull != e->cache_bytes ||
        (e->cache_bytes > 0 && vertex_data < 0x10000ull)) {
        g_h4_cache_mid_guard_fail++;
        return 0;
    }

    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    if (e->cache_bytes > 0) {
        h4_copy_bytes(vertex_data, (u64)&g_h4_vertex_cache[e->cache_offset], e->cache_bytes);
    }
    const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
    if (dt > 0) g_h4_cache_copy_ticks += dt;
    g_h4_current_fast_used = 1;
    return 1;
}

extern "C" u64 PCL_MS_ABI
pcl_h4_scope_passthrough(void* actor, void* source) {
    g_h4_scope_calls++;

    H4Fn fn = g_h4_scope_orig;
    if (!fn) return 0;

    // The detour is process-wide while installed, so only the thread that
    // entered pcl_native_rebuild owns the reuse/cache table. Other threads remain
    // pure pass-through and cannot race any cache state.
    if (g_h4_scope_owner_teb == 0 || get_teb() != g_h4_scope_owner_teb) {
        g_h4_other_thread_calls++;
        return fn(actor, source);
    }
    g_h4_profile_calls++;

    bool first = false;
    bool repeat = false;
    H4SourceEntry* entry = 0;
    const u64 src = (u64)source;
    if (src) {
        entry = h4_source_slot(src, &first);
        repeat = (entry != 0 && !first);
        if (repeat) g_h4_repeat_calls++;
    } else {
        g_h4_null_source_calls++;
    }

    const u32 geometry_state_before = entry ? entry->geometry_state : 0u;

    // 15.11.73: after eight matching stock outputs, use the mid-H4 vertex-loop
    // bypass on ordinary repeats. Every 128th eligible call intentionally remains
    // stock and acts as a canary against late-changing source geometry.
    bool planned_fast = false;
    bool planned_canary = false;
    if (entry && repeat && entry->cache_state == 2u && g_h4_loop_active) {
        if (entry->fast_since_canary + 1u >= H4_CACHE_CANARY_INTERVAL) {
            entry->fast_since_canary = 0;
            planned_canary = true;
            g_h4_cache_canary_calls++;
        } else {
            entry->fast_since_canary++;
            g_h4_current_fast_entry = entry;
            g_h4_current_fast_used = 0;
            planned_fast = true;
        }
    }

    H4SourceEntry* prev_scope_entry = g_h4_current_scope_entry;
    g_h4_current_scope_entry = entry;
    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    const u64 r = fn(actor, source);
    const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
    g_h4_current_scope_entry = prev_scope_entry;

    const bool used_fast = planned_fast && g_h4_current_fast_used != 0;
    g_h4_current_fast_entry = 0;
    g_h4_current_fast_used = 0;

    if (used_fast && entry) {
        g_h4_cache_fast_calls++;
        g_h4_cache_fast_bytes += (i64)entry->cache_bytes;
    }

    // Attribute work by the pre-call two-sample component classification. On
    // 15.11.73 stable_post time now includes the real fast-path timing.
    if (repeat) {
        if (geometry_state_before == 2u) {
            g_h4_stable_post_calls++;
            if (dt > 0) g_h4_stable_post_ticks += dt;
        } else if (geometry_state_before == 3u) {
            g_h4_unstable_post_calls++;
            if (dt > 0) g_h4_unstable_post_ticks += dt;
        } else {
            g_h4_unresolved_repeat_calls++;
            if (dt > 0) g_h4_unresolved_repeat_ticks += dt;
        }
    }

    if (dt > 0) {
        g_h4_total_ticks += dt;
        if (first) g_h4_first_ticks += dt;
        else if (repeat) g_h4_repeat_ticks += dt;
    }

    // Keep the 15.11.71 component-level first/second-stock-output telemetry.
    // Cached calls are never fingerprinted here because their payload is ours.
    if (!used_fast && entry && (first || (repeat && entry->fp_state == 1))) {
        H4PayloadFingerprint fp = {};
        const i64 ht0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
        const bool fp_ok = h4_capture_payload(actor, &fp);
        const i64 hdt = ht0 ? (h4_qpc_now() - ht0) : 0;
        if (hdt > 0) g_h4_fp_hash_ticks += hdt;
        g_h4_fp_checks++;
        if (!fp_ok) {
            g_h4_fp_guard_fail++;
        } else {
            g_h4_fp_index_bytes += (i64)fp.index_bytes;
            g_h4_fp_vertex_bytes += (i64)fp.vertex_bytes;
            if (first || entry->fp_state == 0) {
                entry->bounds_hash = fp.bounds_hash;
                entry->index_hash = fp.index_hash;
                entry->vertex_hash = fp.vertex_hash;
                entry->index_num = fp.index_num;
                entry->vertex_num = fp.vertex_num;
                entry->fp_state = 1;
                entry->geometry_state = 1;
                g_h4_fp_sources_captured++;
            } else if (entry->fp_state == 1) {
                u32 mismatch = 0;
                if (entry->bounds_hash != fp.bounds_hash) mismatch |= 1u;
                if (entry->index_num != fp.index_num) mismatch |= 2u;
                if (entry->vertex_num != fp.vertex_num) mismatch |= 4u;
                if (entry->index_hash != fp.index_hash) mismatch |= 8u;
                if (entry->vertex_hash != fp.vertex_hash) mismatch |= 16u;
                if (mismatch & 1u)  g_h4_fp_bounds_mismatch++;
                if (mismatch & 2u)  g_h4_fp_index_num_mismatch++;
                if (mismatch & 4u)  g_h4_fp_vertex_num_mismatch++;
                if (mismatch & 8u)  g_h4_fp_index_hash_mismatch++;
                if (mismatch & 16u) g_h4_fp_vertex_hash_mismatch++;

                const u32 geometry_mismatch = mismatch & (2u | 4u | 8u | 16u);
                if (geometry_mismatch) {
                    entry->geometry_state = 3;
                    g_h4_fp_geometry_mismatch++;
                    if (!g_h4_fp_first_geometry_mismatch_source) {
                        g_h4_fp_first_geometry_mismatch_source = entry->source;
                        g_h4_fp_first_geometry_mismatch_code = geometry_mismatch;
                    }
                } else {
                    entry->geometry_state = 2;
                    g_h4_fp_geometry_validated++;
                    if (mismatch == 1u) g_h4_fp_bounds_only_mismatch++;
                }

                if (mismatch) {
                    entry->fp_state = 3;
                    g_h4_fp_sources_mismatch++;
                    if (!g_h4_fp_first_mismatch_source) {
                        g_h4_fp_first_mismatch_source = entry->source;
                        g_h4_fp_first_mismatch_code = mismatch;
                    }
                } else {
                    entry->fp_state = 2;
                    g_h4_fp_sources_validated++;
                }
            }
        }
    }

    // Stronger cache proof: hash every STOCK output until the source reaches eight
    // identical vertex payloads. This deliberately ignores bounds and indices because
    // the fast path skips only the vertex conversion loop.
    if (!used_fast && entry && entry->cache_state != 3u && entry->cache_state != 4u) {
        u64 vh = 0, vb = 0, vd = 0;
        u32 vn = 0;
        const i64 pt0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
        const bool vok = h4_capture_vertex_signature(actor, &vh, &vn, &vb, &vd);
        const i64 pdt = pt0 ? (h4_qpc_now() - pt0) : 0;
        if (pdt > 0) g_h4_cache_proof_ticks += pdt;
        g_h4_cache_proof_checks++;

        if (!vok) {
            if (entry->cache_state != 3u) {
                entry->cache_state = 3u;
                g_h4_cache_rejected_sources++;
            }
        } else if ((planned_canary || (planned_fast && !used_fast)) &&
                   entry->cache_state == 2u) {
            if (vn != entry->proof_vertex_num || vh != entry->proof_vertex_hash) {
                entry->cache_state = 3u;
                entry->geometry_state = 3u;
                if (planned_canary) g_h4_cache_canary_mismatch++;
                g_h4_cache_late_demotions++;
            }
        } else if (entry->cache_state == 0u) {
            entry->proof_vertex_hash = vh;
            entry->proof_vertex_num = vn;
            entry->proof_matches = 1u;
            entry->cache_state = 1u;
        } else if (entry->cache_state == 1u) {
            if (vn != entry->proof_vertex_num || vh != entry->proof_vertex_hash) {
                entry->cache_state = 3u;
                entry->geometry_state = 3u;
                g_h4_cache_rejected_sources++;
            } else {
                entry->proof_matches++;
                if (entry->proof_matches >= H4_CACHE_PROOF_MATCHES) {
                    const u64 aligned = (g_h4_vertex_cache_used + 15ull) & ~15ull;
                    if (aligned <= H4_VERTEX_CACHE_CAP &&
                        vb <= H4_VERTEX_CACHE_CAP &&
                        aligned + vb <= H4_VERTEX_CACHE_CAP) {
                        if (vb > 0) h4_copy_bytes((u64)&g_h4_vertex_cache[aligned], vd, vb);
                        entry->cache_offset = aligned;
                        entry->cache_bytes = vb;
                        entry->cache_state = 2u;
                        entry->fast_since_canary = 0;
                        g_h4_vertex_cache_used = aligned + vb;
                        g_h4_cache_promoted_sources++;
                    } else {
                        entry->cache_state = 4u;
                        g_h4_cache_arena_rejects++;
                    }
                }
            }
        }
    }

    if (entry) {
        entry->calls++;
        entry->ticks += dt;
        if (entry->calls > g_h4_max_calls_per_source) {
            g_h4_max_calls_per_source = entry->calls;
            g_h4_max_source_ptr = entry->source;
            g_h4_max_source_ticks = entry->ticks;
        } else if (entry->source == g_h4_max_source_ptr) {
            g_h4_max_source_ticks = entry->ticks;
        }
        if (entry->ticks > g_h4_hot_source_ticks) {
            g_h4_hot_source_ticks = entry->ticks;
            g_h4_hot_source_ptr = entry->source;
            g_h4_hot_source_calls = entry->calls;
        } else if (entry->source == g_h4_hot_source_ptr) {
            g_h4_hot_source_calls = entry->calls;
            g_h4_hot_source_ticks = entry->ticks;
        }
    }
    return r;
}


static inline void h4_emit_u8(u8*& p, u8 v) { *p++ = v; }
static inline void h4_emit_u64(u8*& p, u64 v) { *(u64*)p = v; p += 8; }

static bool h4_build_loop_dispatch(u64 fast_cont) {
    ULONG old_dispatch = 0;
    if (!h4_protect_rwx(g_h4_loop_dispatch, sizeof(g_h4_loop_dispatch), &old_dispatch))
        return false;

    u8* p = g_h4_loop_dispatch;

    // Preserve volatile GPRs that may still be live in the middle of H4.
    h4_emit_u8(p, 0x51);                         // push rcx
    h4_emit_u8(p, 0x52);                         // push rdx
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x50);   // push r8
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x51);   // push r9
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x52);   // push r10
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x53);   // push r11

    // Shadow space; stack is 16-byte aligned at this stock H4 location.
    h4_emit_u8(p, 0x48); h4_emit_u8(p, 0x83); h4_emit_u8(p, 0xEC); h4_emit_u8(p, 0x20);

    // rcx = r14 (the stock H4 actor pointer at RVA 0x45F81DD)
    h4_emit_u8(p, 0x4C); h4_emit_u8(p, 0x89); h4_emit_u8(p, 0xF1);

    // rax = h4_mid_try_fast; call rax
    h4_emit_u8(p, 0x48); h4_emit_u8(p, 0xB8);
    h4_emit_u64(p, (u64)&h4_mid_try_fast);
    h4_emit_u8(p, 0xFF); h4_emit_u8(p, 0xD0);

    h4_emit_u8(p, 0x48); h4_emit_u8(p, 0x83); h4_emit_u8(p, 0xC4); h4_emit_u8(p, 0x20);
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x5B);   // pop r11
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x5A);   // pop r10
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x59);   // pop r9
    h4_emit_u8(p, 0x41); h4_emit_u8(p, 0x58);   // pop r8
    h4_emit_u8(p, 0x5A);                         // pop rdx
    h4_emit_u8(p, 0x59);                         // pop rcx

    // eax != 0 => cache copied, skip the vertex conversion loop.
    h4_emit_u8(p, 0x85); h4_emit_u8(p, 0xC0);   // test eax,eax
    h4_emit_u8(p, 0x75); h4_emit_u8(p, 0x0E);   // jnz +14 (over fallback abs jump)

    h4_emit_abs_jump(p, (u64)g_h4_loop_tramp);
    p += 14;
    h4_emit_abs_jump(p, fast_cont);
    p += 14;

    while ((u64)(p - g_h4_loop_dispatch) < sizeof(g_h4_loop_dispatch))
        *p++ = 0xCC;

    h4_flush_code(g_h4_loop_dispatch, (ULONG)sizeof(g_h4_loop_dispatch));
    (void)old_dispatch; // dispatch remains executable for DLL lifetime
    return true;
}

static i64 h4_loop_install(u64 base) {
    if (g_h4_loop_active) return -101;
    if (!h4_resolve_patch_api()) return -102;

    const u64 target = base + 0x045F81DDull;
    const u64 fast_cont = base + 0x045F84D5ull;
    const u8 stock_sig[16] = {
        0x8B,0x87,0x40,0x01,0x00,0x00,
        0x89,0x44,0x24,0x30,
        0x8B,0x87,0xC4,0x01,0x00,0x00
    };
    if (!h4_bytes_match(target, stock_sig, 16)) return -103;

    ULONG old_tramp = 0, old_target = 0;
    if (!h4_protect_rwx(g_h4_loop_tramp, sizeof(g_h4_loop_tramp), &old_tramp))
        return -104;
    if (!h4_protect_rwx((void*)target, 16, &old_target)) {
        h4_restore_protection(g_h4_loop_tramp, sizeof(g_h4_loop_tramp), old_tramp);
        return -105;
    }

    for (u32 i = 0; i < 16; ++i) {
        const u8 b = rd<u8>(target + i);
        g_h4_loop_saved[i] = b;
        g_h4_loop_tramp[i] = b;
    }
    h4_emit_abs_jump(g_h4_loop_tramp + 16, target + 16);
    for (u32 i = 30; i < sizeof(g_h4_loop_tramp); ++i) g_h4_loop_tramp[i] = 0xCC;
    h4_flush_code(g_h4_loop_tramp, (ULONG)sizeof(g_h4_loop_tramp));

    if (!h4_build_loop_dispatch(fast_cont)) {
        h4_restore_protection((void*)target, 16, old_target);
        return -106;
    }

    u8 patch[16];
    for (u32 i = 0; i < 16; ++i) patch[i] = 0x90;
    h4_emit_abs_jump(patch, (u64)g_h4_loop_dispatch);
    for (u32 i = 0; i < 16; ++i) wr<u8>(target + i, patch[i]);
    h4_flush_code((void*)target, 16);
    h4_restore_protection((void*)target, 16, old_target);

    (void)old_tramp;
    g_h4_loop_fast_cont = fast_cont;
    g_h4_loop_active = 1;
    g_h4_loop_stock_restored = 0;
    return 1;
}

static i64 h4_loop_restore(u64 base) {
    const u64 target = base + 0x045F81DDull;
    const u8 stock_sig[16] = {
        0x8B,0x87,0x40,0x01,0x00,0x00,
        0x89,0x44,0x24,0x30,
        0x8B,0x87,0xC4,0x01,0x00,0x00
    };

    if (!g_h4_loop_active) {
        g_h4_loop_stock_restored = h4_bytes_match(target, stock_sig, 16) ? 1 : 0;
        return g_h4_loop_stock_restored ? 0 : -111;
    }

    const u8 detour_prefix[6] = {0xFF,0x25,0x00,0x00,0x00,0x00};
    if (!h4_bytes_match(target, detour_prefix, 6) ||
        rd<u64>(target + 6) != (u64)g_h4_loop_dispatch) {
        g_h4_loop_stock_restored = 0;
        return -112;
    }

    ULONG old_target = 0;
    if (!h4_protect_rwx((void*)target, 16, &old_target)) {
        g_h4_loop_stock_restored = 0;
        return -113;
    }
    for (u32 i = 0; i < 16; ++i) wr<u8>(target + i, g_h4_loop_saved[i]);
    h4_flush_code((void*)target, 16);
    h4_restore_protection((void*)target, 16, old_target);

    g_h4_loop_stock_restored = h4_bytes_match(target, stock_sig, 16) ? 1 : 0;
    if (g_h4_loop_stock_restored) {
        g_h4_loop_active = 0;
        g_h4_loop_fast_cont = 0;
        return 1;
    }
    return -114;
}


static inline void h4_emit_abs_call(u8*& p, u64 dst) {
    *p++ = 0x48; *p++ = 0xB8; *(u64*)p = dst; p += 8; // mov rax,imm64
    *p++ = 0xFF; *p++ = 0xD0;                         // call rax
}
static inline void h4_emit_bytes(u8*& p, const u8* b, u32 n) {
    for (u32 i=0;i<n;++i) *p++ = b[i];
}

extern "C" u64 PCL_MS_ABI
pcl_h4_post_vertex_copy_profile(void* dst, const void* src, u64 bytes) {
    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    const u64 r = g_h4_post_bulk_copy_orig ? g_h4_post_bulk_copy_orig(dst, src, bytes) : 0;
    const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
    g_h4_post_vertex_copy_calls++;
    if (dt > 0) g_h4_post_vertex_copy_ticks += dt;
    return r;
}

extern "C" u64 PCL_MS_ABI
pcl_h4_post_index_copy_profile(void* dst, const void* src, u64 bytes) {
    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    const u64 r = g_h4_post_bulk_copy_orig ? g_h4_post_bulk_copy_orig(dst, src, bytes) : 0;
    const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
    g_h4_post_index_copy_calls++;
    if (dt > 0) g_h4_post_index_copy_ticks += dt;
    return r;
}

extern "C" u64 PCL_MS_ABI
pcl_h4_post_component_build_profile(void* component, u64 section, void* payload) {
    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    g_h4_component_build_depth++;
    const u64 r = g_h4_post_component_build_orig ? g_h4_post_component_build_orig(component, section, payload) : 0;
    g_h4_component_build_depth--;
    const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
    g_h4_post_component_build_calls++;
    if (dt > 0) g_h4_post_component_build_ticks += dt;
    return r;
}

extern "C" u64 PCL_MS_ABI
pcl_h4_post_component_final_profile(void* component, u64 flag) {
    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    const u64 r = g_h4_post_component_final_orig ? g_h4_post_component_final_orig(component, flag) : 0;
    const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
    g_h4_post_component_final_calls++;
    if (dt > 0) g_h4_post_component_final_ticks += dt;
    return r;
}

static bool h4_post_build_dispatches(u64 base) {
    const u64 vcont = base + 0x045F85A6ull;
    const u64 icont = base + 0x045F863Aull;
    const u64 bcont = base + 0x045F869Bull;
    const u64 fcont = base + 0x045F86B2ull;
    ULONG old = 0;

    if (!h4_protect_rwx(g_h4_post_vertex_copy_dispatch, sizeof(g_h4_post_vertex_copy_dispatch), &old)) return false;
    {
        u8* p = g_h4_post_vertex_copy_dispatch;
        const u8 a[] = {0x49,0x8B,0x17, 0x48,0x8B,0x4D,0x10}; // mov rdx,[r15]; mov rcx,[rbp+10]
        const u8 z[] = {0x41,0x8B,0x9E,0xB0,0x04,0x00,0x00}; // mov ebx,[r14+4b0]
        h4_emit_bytes(p,a,sizeof(a)); h4_emit_abs_call(p,(u64)&pcl_h4_post_vertex_copy_profile); h4_emit_bytes(p,z,sizeof(z));
        h4_emit_abs_jump(p,vcont); p += 14; while ((u64)(p-g_h4_post_vertex_copy_dispatch)<sizeof(g_h4_post_vertex_copy_dispatch)) *p++=0xCC;
        h4_flush_code(g_h4_post_vertex_copy_dispatch,(ULONG)sizeof(g_h4_post_vertex_copy_dispatch));
    }
    if (!h4_protect_rwx(g_h4_post_index_copy_dispatch, sizeof(g_h4_post_index_copy_dispatch), &old)) return false;
    {
        u8* p = g_h4_post_index_copy_dispatch;
        const u8 a[] = {0x49,0x8B,0x14,0x24, 0x48,0x8B,0x4D,0x20}; // mov rdx,[r12]; mov rcx,[rbp+20]
        const u8 z[] = {0x41,0x0F,0x10,0x86,0x70,0x04,0x00,0x00}; // movups xmm0,[r14+470]
        h4_emit_bytes(p,a,sizeof(a)); h4_emit_abs_call(p,(u64)&pcl_h4_post_index_copy_profile); h4_emit_bytes(p,z,sizeof(z));
        h4_emit_abs_jump(p,icont); p += 14; while ((u64)(p-g_h4_post_index_copy_dispatch)<sizeof(g_h4_post_index_copy_dispatch)) *p++=0xCC;
        h4_flush_code(g_h4_post_index_copy_dispatch,(ULONG)sizeof(g_h4_post_index_copy_dispatch));
    }
    if (!h4_protect_rwx(g_h4_post_build_dispatch, sizeof(g_h4_post_build_dispatch), &old)) return false;
    {
        u8* p = g_h4_post_build_dispatch;
        const u8 a[] = {0x4C,0x8D,0x45,0x10, 0x33,0xD2, 0x49,0x8B,0xCD}; // lea r8,[rbp+10]; xor edx,edx; mov rcx,r13
        h4_emit_bytes(p,a,sizeof(a)); h4_emit_abs_call(p,(u64)&pcl_h4_post_component_build_profile);
        h4_emit_abs_jump(p,bcont); p += 14; while ((u64)(p-g_h4_post_build_dispatch)<sizeof(g_h4_post_build_dispatch)) *p++=0xCC;
        h4_flush_code(g_h4_post_build_dispatch,(ULONG)sizeof(g_h4_post_build_dispatch));
    }
    if (!h4_protect_rwx(g_h4_post_final_dispatch, sizeof(g_h4_post_final_dispatch), &old)) return false;
    {
        u8* p = g_h4_post_final_dispatch;
        const u8 a[] = {0x33,0xD2, 0x49,0x8B,0xCD}; // xor edx,edx; mov rcx,r13
        const u8 z[] = {0x48,0x8B,0x4D,0x20};       // mov rcx,[rbp+20]
        h4_emit_bytes(p,a,sizeof(a)); h4_emit_abs_call(p,(u64)&pcl_h4_post_component_final_profile); h4_emit_bytes(p,z,sizeof(z));
        h4_emit_abs_jump(p,fcont); p += 14; while ((u64)(p-g_h4_post_final_dispatch)<sizeof(g_h4_post_final_dispatch)) *p++=0xCC;
        h4_flush_code(g_h4_post_final_dispatch,(ULONG)sizeof(g_h4_post_final_dispatch));
    }
    return true;
}

static bool h4_post_patch_one(u64 target, const u8* stock, u32 len, u8* saved, u8* dispatch) {
    if (!h4_bytes_match(target,stock,len)) return false;
    ULONG old=0; if (!h4_protect_rwx((void*)target,len,&old)) return false;
    for (u32 i=0;i<len;++i) { saved[i]=rd<u8>(target+i); wr<u8>(target+i,0x90); }
    u8 patch[14]; h4_emit_abs_jump(patch,(u64)dispatch); for (u32 i=0;i<14;++i) wr<u8>(target+i,patch[i]);
    h4_flush_code((void*)target,len); h4_restore_protection((void*)target,len,old); return true;
}

static bool h4_post_restore_one(u64 target, const u8* stock, u32 len, const u8* saved, u8* dispatch) {
    if (h4_bytes_match(target,stock,len)) return true;
    const u8 detour_prefix[6]={0xFF,0x25,0,0,0,0};
    if (!h4_bytes_match(target,detour_prefix,6) || rd<u64>(target+6)!=(u64)dispatch) return false;
    ULONG old=0; if (!h4_protect_rwx((void*)target,len,&old)) return false;
    for (u32 i=0;i<len;++i) wr<u8>(target+i,saved[i]); h4_flush_code((void*)target,len); h4_restore_protection((void*)target,len,old);
    return h4_bytes_match(target,stock,len);
}

static i64 h4_post_restore(u64 base);

static i64 h4_post_install(u64 base) {
    if (g_h4_post_active) return -201;
    if (!h4_resolve_patch_api()) return -202;
    g_h4_post_bulk_copy_orig = (H4BulkCopyFn)(base + 0x06649A64ull);
    g_h4_post_component_build_orig = (H4ComponentBuildFn)(base + 0x0400E8E0ull);
    g_h4_post_component_final_orig = (H4ComponentFinalFn)(base + 0x0362B770ull);
    if (!h4_post_build_dispatches(base)) return -203;

    const u8 vsig[19]={0x49,0x8B,0x17,0x48,0x8B,0x4D,0x10,0xE8,0xC5,0x14,0x05,0x02,0x41,0x8B,0x9E,0xB0,0x04,0x00,0x00};
    const u8 isig[21]={0x49,0x8B,0x14,0x24,0x48,0x8B,0x4D,0x20,0xE8,0x32,0x14,0x05,0x02,0x41,0x0F,0x10,0x86,0x70,0x04,0x00,0x00};
    const u8 bsig[14]={0x4C,0x8D,0x45,0x10,0x33,0xD2,0x49,0x8B,0xCD,0xE8,0x45,0x62,0xA1,0xFF};
    const u8 fsig[15]={0x33,0xD2,0x49,0x8B,0xCD,0xE8,0xC3,0x30,0x03,0xFF,0x90,0x48,0x8B,0x4D,0x20};
    if (!h4_post_patch_one(base+0x045F8593ull,vsig,19,g_h4_post_vertex_copy_saved,g_h4_post_vertex_copy_dispatch)) return -204;
    if (!h4_post_patch_one(base+0x045F8625ull,isig,21,g_h4_post_index_copy_saved,g_h4_post_index_copy_dispatch)) { g_h4_post_active=1; h4_post_restore(base); return -205; }
    if (!h4_post_patch_one(base+0x045F868Dull,bsig,14,g_h4_post_build_saved,g_h4_post_build_dispatch)) { g_h4_post_active=1; h4_post_restore(base); return -206; }
    if (!h4_post_patch_one(base+0x045F86A3ull,fsig,15,g_h4_post_final_saved,g_h4_post_final_dispatch)) { g_h4_post_active=1; h4_post_restore(base); return -207; }
    g_h4_post_active=1; g_h4_post_stock_restored=0; return 1;
}

static i64 h4_post_restore(u64 base) {
    const u8 vsig[19]={0x49,0x8B,0x17,0x48,0x8B,0x4D,0x10,0xE8,0xC5,0x14,0x05,0x02,0x41,0x8B,0x9E,0xB0,0x04,0x00,0x00};
    const u8 isig[21]={0x49,0x8B,0x14,0x24,0x48,0x8B,0x4D,0x20,0xE8,0x32,0x14,0x05,0x02,0x41,0x0F,0x10,0x86,0x70,0x04,0x00,0x00};
    const u8 bsig[14]={0x4C,0x8D,0x45,0x10,0x33,0xD2,0x49,0x8B,0xCD,0xE8,0x45,0x62,0xA1,0xFF};
    const u8 fsig[15]={0x33,0xD2,0x49,0x8B,0xCD,0xE8,0xC3,0x30,0x03,0xFF,0x90,0x48,0x8B,0x4D,0x20};
    bool ok=true;
    if (g_h4_post_active) {
        ok &= h4_post_restore_one(base+0x045F86A3ull,fsig,15,g_h4_post_final_saved,g_h4_post_final_dispatch);
        ok &= h4_post_restore_one(base+0x045F868Dull,bsig,14,g_h4_post_build_saved,g_h4_post_build_dispatch);
        ok &= h4_post_restore_one(base+0x045F8625ull,isig,21,g_h4_post_index_copy_saved,g_h4_post_index_copy_dispatch);
        ok &= h4_post_restore_one(base+0x045F8593ull,vsig,19,g_h4_post_vertex_copy_saved,g_h4_post_vertex_copy_dispatch);
    } else {
        ok = h4_bytes_match(base+0x045F8593ull,vsig,19) && h4_bytes_match(base+0x045F8625ull,isig,21) &&
             h4_bytes_match(base+0x045F868Dull,bsig,14) && h4_bytes_match(base+0x045F86A3ull,fsig,15);
    }
    g_h4_post_stock_restored = ok ? 1 : 0;
    if (ok) { g_h4_post_active=0; return 1; }
    return -208;
}


// ---------------------------------------------------------------------------
// 15.11.75 nested profiling of 0x400E8E0 helper calls.
// Entry patches use mov rax,imm64 / jmp rax (12 bytes). RAX is volatile at a Win64
// function boundary; trampolines jump back with the register-preserving FF25 form.
static inline bool h4_nested_should_profile() {
    return g_h4_component_build_depth > 0 && g_h4_scope_owner_teb != 0 &&
           g_h4_scope_owner_teb == get_teb();
}

extern "C" u64 PCL_MS_ABI pcl_h4_nested_grow_profile(
    u64 a1,u64 a2,u64 a3,void* a4,void* a5,void* a6) {
    const bool p = h4_nested_should_profile(); const i64 t0 = p && g_h4_qpf>0 ? h4_qpc_now() : 0;
    const u64 r = g_h4_nested_grow_orig ? g_h4_nested_grow_orig(a1,a2,a3,a4,a5,a6) : 0;
    if (p) { const i64 dt=t0?(h4_qpc_now()-t0):0; g_h4_nested_grow_calls++; if(dt>0) g_h4_nested_grow_ticks+=dt; }
    return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_nested_payload_a_profile(void* a,void* b) {
    const bool p=h4_nested_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_nested_payload_a_orig?g_h4_nested_payload_a_orig(a,b):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_nested_payload_a_calls++;if(dt>0)g_h4_nested_payload_a_ticks+=dt;} return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_nested_payload_b_profile(void* a,void* b) {
    const bool p=h4_nested_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_nested_payload_b_orig?g_h4_nested_payload_b_orig(a,b):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_nested_payload_b_calls++;if(dt>0)g_h4_nested_payload_b_ticks+=dt;} return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_nested_recalc_profile(void* a) {
    const bool p=h4_nested_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_nested_recalc_orig?g_h4_nested_recalc_orig(a):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_nested_recalc_calls++;if(dt>0)g_h4_nested_recalc_ticks+=dt;} return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_nested_update_profile(void* a) {
    const bool p=h4_nested_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    i64 before_num = -1;
    if (p) {
        const u64 component = (u64)a;
        if (component >= 0x10000ull) {
            const i32 n = rd<i32>(component + 0x5F0ull);
            const i32 m = rd<i32>(component + 0x5F4ull);
            if (n >= 0 && m >= n && m <= 10000000) before_num = (i64)n;
            else g_h4_update_card_guard_fail++;
        } else g_h4_update_card_guard_fail++;
        // Install data-only vtable slot wrappers before the stock update reaches
        // its two hot-path virtual calls. Failure is measurement-only and leaves
        // stock behavior untouched.
        h4_vtable_ensure_for_component(component);
        g_h4_update_depth++;
    }
    const u64 r=g_h4_nested_update_orig?g_h4_nested_update_orig(a):0;
    if (p) {
        g_h4_update_depth--;
        if (before_num >= 0) {
            g_h4_update_card_before_items += before_num;
            if (before_num > 0) g_h4_update_card_nonzero_calls++; else g_h4_update_card_zero_calls++;
            if (before_num > g_h4_update_card_max_before) g_h4_update_card_max_before = before_num;
        }
        const u64 component = (u64)a;
        if (component >= 0x10000ull) {
            const i32 n2 = rd<i32>(component + 0x5F0ull);
            const i32 m2 = rd<i32>(component + 0x5F4ull);
            if (n2 >= 0 && m2 >= n2 && m2 <= 10000000) g_h4_update_card_after_items += (i64)n2;
            else g_h4_update_card_guard_fail++;
        } else g_h4_update_card_guard_fail++;
        const i64 dt=t0?(h4_qpc_now()-t0):0; g_h4_nested_update_calls++; if(dt>0)g_h4_nested_update_ticks+=dt;
    }
    return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_nested_tail_profile(void* a) {
    const bool p=h4_nested_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_nested_tail_orig?g_h4_nested_tail_orig(a):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_nested_tail_calls++;if(dt>0)g_h4_nested_tail_ticks+=dt;} return r;
}

static inline bool h4_update_tail_should_profile() {
    return g_h4_update_depth > 0 && g_h4_scope_owner_teb && get_teb() == g_h4_scope_owner_teb;
}


static H4VTableEntry* h4_vtable_find(u64 vt) {
    const i64 n = g_h4_vt_count;
    for (i64 i=0; i<n && i<(i64)H4_VT_CAP; ++i) if (g_h4_vt[i].vtable == vt) return &g_h4_vt[i];
    return 0;
}

static bool h4_write_ptr_slot(u64 slot, u64 expected, u64 replacement) {
    if (slot < 0x10000ull || rd<u64>(slot) != expected) return false;
    ULONG old=0;
    if (!h4_protect_rwx((void*)slot, 8, &old)) return false;
    wr<u64>(slot, replacement);
    h4_restore_protection((void*)slot, 8, old);
    return rd<u64>(slot) == replacement;
}

static bool h4_restore_ptr_slot(u64 slot, u64 wrapper, u64 original) {
    const u64 cur = rd<u64>(slot);
    if (cur == original) return true;
    if (cur != wrapper) return false;
    ULONG old=0;
    if (!h4_protect_rwx((void*)slot, 8, &old)) return false;
    wr<u64>(slot, original);
    h4_restore_protection((void*)slot, 8, old);
    return rd<u64>(slot) == original;
}

extern "C" u64 PCL_MS_ABI pcl_h4_v2d0_profile(void* a) {
    const u64 obj=(u64)a, vt=obj>=0x10000ull?rd<u64>(obj):0;
    H4VTableEntry* e=h4_vtable_find(vt);
    H4VFuncOneFn orig=e?(H4VFuncOneFn)e->orig_2d0:0;
    if(!orig){ g_h4_vt_guard_fail++; return 0; }
    const bool p=h4_update_tail_should_profile();
    const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=orig(a);
    if(p){ const i64 dt=t0?(h4_qpc_now()-t0):0; g_h4_v2d0_calls++; if(dt>0) g_h4_v2d0_ticks+=dt; }
    return r;
}

extern "C" u64 PCL_MS_ABI pcl_h4_v2b0_profile(void* a) {
    const u64 obj=(u64)a, vt=obj>=0x10000ull?rd<u64>(obj):0;
    H4VTableEntry* e=h4_vtable_find(vt);
    H4VFuncOneFn orig=e?(H4VFuncOneFn)e->orig_2b0:0;
    if(!orig){ g_h4_vt_guard_fail++; return 0; }

    const bool p=h4_update_tail_should_profile();
    bool heavy=false;
    if(p && obj>=0x10000ull) {
        // Target RVA 0x3B9F4A0 begins with test byte ptr [rcx+0xD9],0x09.
        // If either bit is already set the function jumps directly to return.
        const u8 flags=rd<u8>(obj+0xD9ull);
        heavy=(flags & 0x09u)==0;
    }

    const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    if(p && heavy) g_h4_v2b0_heavy_context++;
    const u64 r=orig(a);
    if(p && heavy) g_h4_v2b0_heavy_context--;
    if(p){
        const i64 dt=t0?(h4_qpc_now()-t0):0;
        g_h4_v2b0_calls++;
        if(dt>0) g_h4_v2b0_ticks+=dt;
        if(heavy) {
            g_h4_v2b0_heavy_calls++;
            if(dt>0) g_h4_v2b0_heavy_ticks+=dt;

            // 15.11.88: sample the target structure AFTER the heavy call.
            // Static disassembly shows +0x68/+0x70 is the 0x100-byte entry TArray,
            // but the target populates/normalizes it internally before its loops.
            // Pre-call sampling in 15.11.86 therefore correctly saw zero entries.
            const i32 n=rd<i32>(obj+0x70ull);
            const u64 entries=rd<u64>(obj+0x68ull);
            if(rd<u64>(obj+0x310ull)!=0) g_h4_v2b0_ptr310_nonzero++;
            if(n>=0 && n<=4096 && (n==0 || entries>=0x10000ull)) {
                g_h4_v2b0_heavy_entries += (i64)n;
                if((i64)n>g_h4_v2b0_heavy_entry_max) g_h4_v2b0_heavy_entry_max=(i64)n;
                for(i32 i=0;i<n;++i) {
                    const u64 ent=entries+(u64)(u32)i*0x100ull;
                    const i32 inner_num=rd<i32>(ent+0x48ull);
                    if(inner_num==0) g_h4_v2b0_zero_inner_entries++;

                    // Helper RVA 0x3BA3970 reads entry+0x38 as the source vector count.
                    // Sum it for every post-call entry so we can estimate conversion work.
                    const i32 sub=rd<i32>(ent+0x38ull);
                    if(sub>=0 && sub<=10000000) {
                        g_h4_v2b0_subcount_total += (i64)sub;
                        if((i64)sub>g_h4_v2b0_subcount_max) g_h4_v2b0_subcount_max=(i64)sub;
                    } else {
                        g_h4_v2b0_structure_guard_fail++;
                    }
                }
            } else {
                g_h4_v2b0_structure_guard_fail++;
            }
        } else {
            g_h4_v2b0_early_calls++;
            if(dt>0) g_h4_v2b0_early_ticks+=dt;
        }
    }
    return r;
}

static bool h4_vtable_ensure_for_component(u64 component) {
    if (component < 0x10000ull) { g_h4_vt_guard_fail++; return false; }
    const u64 obj = rd<u64>(component + 0x588ull);
    if (!obj) return false; // legitimate branch; no slot can be patched yet
    if (obj < 0x10000ull) { g_h4_vt_guard_fail++; return false; }
    const u64 vt = rd<u64>(obj);
    if (vt < 0x10000ull) { g_h4_vt_guard_fail++; return false; }
    if (h4_vtable_find(vt)) return true;
    if (g_h4_vt_count >= (i64)H4_VT_CAP) { g_h4_vt_patch_fail++; return false; }
    const u64 orig_d0 = rd<u64>(vt + 0x2D0ull);
    const u64 orig_b0 = rd<u64>(vt + 0x2B0ull);

    // Capture before either vtable slot is modified. Current executable
    // SizeOfImage is guarded elsewhere as 0x090A0000; use that only to decide
    // whether it is safe to fingerprint target bytes. Unknown/out-of-image
    // targets are still reported, but are never dereferenced here.
    const u64 image_base = get_main_module_base();
    const u64 image_end = image_base ? (image_base + 0x090A0000ull) : 0;
    if (g_h4_vt_first == 0) {
        g_h4_vt_first = vt;
        g_h4_vt_first_rva = (image_base && vt >= image_base && vt < image_end) ? (vt - image_base) : 0;
        g_h4_v2d0_target = orig_d0;
        g_h4_v2d0_target_rva = (image_base && orig_d0 >= image_base && orig_d0 < image_end) ? (orig_d0 - image_base) : 0;
        g_h4_v2b0_target = orig_b0;
        g_h4_v2b0_target_rva = (image_base && orig_b0 >= image_base && orig_b0 + 16ull <= image_end) ? (orig_b0 - image_base) : 0;
        if (g_h4_v2b0_target_rva != 0) {
            g_h4_v2b0_target_in_image = 1;
            g_h4_v2b0_sig0 = rd<u32>(orig_b0 + 0ull);
            g_h4_v2b0_sig1 = rd<u32>(orig_b0 + 4ull);
            g_h4_v2b0_sig2 = rd<u32>(orig_b0 + 8ull);
            g_h4_v2b0_sig3 = rd<u32>(orig_b0 + 12ull);
        }
    } else if (orig_b0 != g_h4_v2b0_target) {
        g_h4_v2b0_target_mismatch++;
    }
    g_h4_vt_capture_count++;

    if (orig_d0 < 0x10000ull || orig_b0 < 0x10000ull ||
        orig_d0 == (u64)&pcl_h4_v2d0_profile || orig_b0 == (u64)&pcl_h4_v2b0_profile) {
        g_h4_vt_guard_fail++; return false;
    }
    const i64 idx = g_h4_vt_count;
    g_h4_vt[idx].vtable = vt;
    g_h4_vt[idx].orig_2d0 = orig_d0;
    g_h4_vt[idx].orig_2b0 = orig_b0;
    g_h4_vt_count = idx + 1; // publish originals before either slot can call us
    if (!h4_write_ptr_slot(vt + 0x2D0ull, orig_d0, (u64)&pcl_h4_v2d0_profile)) {
        g_h4_vt_count = idx; g_h4_vt[idx].vtable=0; g_h4_vt_patch_fail++; return false;
    }
    if (!h4_write_ptr_slot(vt + 0x2B0ull, orig_b0, (u64)&pcl_h4_v2b0_profile)) {
        h4_restore_ptr_slot(vt + 0x2D0ull, (u64)&pcl_h4_v2d0_profile, orig_d0);
        g_h4_vt_count = idx; g_h4_vt[idx].vtable=0; g_h4_vt_patch_fail++; return false;
    }
    g_h4_vt_patched++;
    if (g_h4_vt_count > g_h4_vt_peak) g_h4_vt_peak = g_h4_vt_count;
    return true;
}

static bool h4_vtable_restore_all() {
    if (!h4_resolve_patch_api()) return g_h4_vt_count == 0;
    bool ok=true;
    for (i64 i=g_h4_vt_count-1; i>=0; --i) {
        H4VTableEntry &e=g_h4_vt[i];
        bool a=h4_restore_ptr_slot(e.vtable+0x2B0ull,(u64)&pcl_h4_v2b0_profile,e.orig_2b0);
        bool b=h4_restore_ptr_slot(e.vtable+0x2D0ull,(u64)&pcl_h4_v2d0_profile,e.orig_2d0);
        if(!a||!b){ ok=false; g_h4_vt_restore_fail++; }
        if(a&&b){ e.vtable=0; e.orig_2d0=0; e.orig_2b0=0; }
    }
    if(ok) g_h4_vt_count=0;
    return ok;
}
extern "C" u64 PCL_MS_ABI pcl_h4_ut_tail_profile(void* a) {
    const bool p=h4_update_tail_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_ut_tail_orig?g_h4_ut_tail_orig(a):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_ut_tail_calls++;if(dt>0)g_h4_ut_tail_ticks+=dt;} return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_ut_pre_profile(void* a) {
    const bool p=h4_update_tail_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_ut_pre_orig?g_h4_ut_pre_orig(a):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_ut_pre_calls++;if(dt>0)g_h4_ut_pre_ticks+=dt;} return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_ut_dirty_profile(void* a,u64 b) {
    const bool p=h4_update_tail_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_ut_dirty_orig?g_h4_ut_dirty_orig(a,b):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_ut_dirty_calls++;if(dt>0)g_h4_ut_dirty_ticks+=dt;} return r;
}
extern "C" u64 PCL_MS_ABI pcl_h4_ut_dispatch_profile(void* a,u64 b) {
    const bool p=h4_update_tail_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    const u64 r=g_h4_ut_dispatch_orig?g_h4_ut_dispatch_orig(a,b):0;
    if(p){const i64 dt=t0?(h4_qpc_now()-t0):0;g_h4_ut_dispatch_calls++;if(dt>0)g_h4_ut_dispatch_ticks+=dt;} return r;
}

static inline void h4_emit_mov_rax_jmp(u8* out, u64 dst) {
    out[0]=0x48; out[1]=0xB8; *(u64*)(out+2)=dst; out[10]=0xFF; out[11]=0xE0;
}

static bool h4_nested_patch_one(u64 target,const u8* stock,u32 len,u8* saved,u8* tramp,u64 wrapper) {
    if(len<12 || len+14>64 || !h4_bytes_match(target,stock,len)) return false;
    ULONG oldt=0, oldc=0;
    if(!h4_protect_rwx(tramp,64,&oldt)) return false;
    for(u32 i=0;i<len;++i){ saved[i]=rd<u8>(target+i); tramp[i]=saved[i]; }
    h4_emit_abs_jump(tramp+len,target+len);
    for(u32 i=len+14;i<64;++i) tramp[i]=0xCC;
    h4_flush_code(tramp,64);
    if(!h4_protect_rwx((void*)target,len,&oldc)){ h4_restore_protection(tramp,64,oldt); return false; }
    for(u32 i=0;i<len;++i) wr<u8>(target+i,0x90);
    u8 p[12]; h4_emit_mov_rax_jmp(p,wrapper); for(u32 i=0;i<12;++i) wr<u8>(target+i,p[i]);
    h4_flush_code((void*)target,len); h4_restore_protection((void*)target,len,oldc);
    (void)oldt; // trampoline stays executable while DLL is loaded
    return true;
}

static bool h4_nested_restore_one(u64 target,const u8* stock,u32 len,const u8* saved,u64 wrapper) {
    if(h4_bytes_match(target,stock,len)) return true;
    if(rd<u8>(target)!=0x48 || rd<u8>(target+1)!=0xB8 || rd<u64>(target+2)!=wrapper ||
       rd<u8>(target+10)!=0xFF || rd<u8>(target+11)!=0xE0) return false;
    ULONG old=0; if(!h4_protect_rwx((void*)target,len,&old)) return false;
    for(u32 i=0;i<len;++i) wr<u8>(target+i,saved[i]);
    h4_flush_code((void*)target,len); h4_restore_protection((void*)target,len,old);
    return h4_bytes_match(target,stock,len);
}

static bool h4_tail_site_patch(u64 target, const u8* stock, u8* saved, u64 wrapper) {
    const u32 len = 14;
    if (!h4_bytes_match(target, stock, len)) return false;
    ULONG old = 0;
    if (!h4_protect_rwx((void*)target, len, &old)) return false;
    for (u32 i=0;i<len;++i) saved[i] = rd<u8>(target+i);
    u8 patch[14]; h4_emit_abs_jump(patch, wrapper);
    for (u32 i=0;i<len;++i) wr<u8>(target+i, patch[i]);
    h4_flush_code((void*)target, len);
    h4_restore_protection((void*)target, len, old);
    return true;
}

static bool h4_tail_site_restore(u64 target, const u8* stock, const u8* saved, u64 wrapper) {
    const u32 len = 14;
    if (h4_bytes_match(target, stock, len)) return true;
    const u8 detour_prefix[6]={0xFF,0x25,0,0,0,0};
    if (!h4_bytes_match(target,detour_prefix,6) || rd<u64>(target+6)!=wrapper) return false;
    ULONG old=0;
    if (!h4_protect_rwx((void*)target,len,&old)) return false;
    for (u32 i=0;i<len;++i) wr<u8>(target+i,saved[i]);
    h4_flush_code((void*)target,len);
    h4_restore_protection((void*)target,len,old);
    return h4_bytes_match(target,stock,len);
}

static i64 h4_nested_restore(u64 base) {
    const u8 upd[12]={0x40,0x53,0x56,0x57,0x41,0x54,0x41,0x56,0x48,0x83,0xEC,0x50};
    // update RVA 0x40119F0 exits through a tail-jump at 0x4011C7D when the
    // synchronous branch is used. The nine bytes after the 5-byte jmp are INT3
    // padding, so this exact 14-byte site can safely host our RIP-indirect jump.
    const u8 tail_site[14]={0xE9,0xEE,0x85,0x63,0xFF,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC};
    bool ok=true;
    ok &= h4_vtable_restore_all();
    ok &= h4_tail_site_restore(base+0x04011C7Dull,tail_site,g_h4_ut_tail_saved,(u64)&pcl_h4_ut_tail_profile);
    ok &= h4_nested_restore_one(base+0x040119F0ull,upd,12,g_h4_nested_update_saved,(u64)&pcl_h4_nested_update_profile);
    g_h4_ut_tail_site_stock_restored = h4_bytes_match(base+0x04011C7Dull,tail_site,14) ? 1 : 0;
    g_h4_nested_stock_restored=ok?1:0;
    if(ok){g_h4_ut_tail_site_active=0;g_h4_nested_active=0;return 1;}
    return -318;
}

static i64 h4_nested_install(u64 base) {
    if(g_h4_nested_active) return -301;
    if(!h4_resolve_patch_api()) return -302;
    const u8 upd[12]={0x40,0x53,0x56,0x57,0x41,0x54,0x41,0x56,0x48,0x83,0xEC,0x50};
    const u8 tail_site[14]={0xE9,0xEE,0x85,0x63,0xFF,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC};
    if(!h4_nested_patch_one(base+0x040119F0ull,upd,12,g_h4_nested_update_saved,g_h4_nested_update_tramp,(u64)&pcl_h4_nested_update_profile)) return -307;
    g_h4_nested_update_orig=(H4NestedOneFn)(void*)g_h4_nested_update_tramp;

    // Do NOT detour 0x364A270 itself. 15.11.78 copied its relative CALL into a
    // trampoline without relocation, so the copied E8 displacement targeted the
    // wrong address. 15.11.80 instead intercepts only the tail-jump in 0x40119F0.
    g_h4_ut_tail_orig=(H4NestedOneFn)(base+0x0364A270ull);
    if(!h4_tail_site_patch(base+0x04011C7Dull,tail_site,g_h4_ut_tail_saved,(u64)&pcl_h4_ut_tail_profile)) {
        h4_nested_restore(base);
        return -311;
    }
    g_h4_ut_tail_site_active=1;
    g_h4_ut_tail_site_stock_restored=0;
    g_h4_nested_active=1;
    g_h4_nested_stock_restored=0;
    return 1;
}


// ---------------------------------------------------------------------------
// 15.11.88 heavy +0x2B0 child profiler. First-level exclusivity prevents a
// child helper reached from another profiled helper from being double-counted.
static inline bool h4_v2b0_child_should_profile() {
    return g_h4_v2b0_heavy_context > 0 && g_h4_v2b0_child_depth == 0 &&
           g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();
}
#define H4_V2B0_CHILD_WRAPPER(NAME, ORIG, CALLS, TICKS) \
extern "C" u64 PCL_MS_ABI NAME(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) { \
    const bool p=h4_v2b0_child_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0; \
    if(p) g_h4_v2b0_child_depth++; \
    const u64 r=(ORIG)?(ORIG)(a1,a2,a3,a4,a5,a6):0; \
    if(p){ g_h4_v2b0_child_depth--; const i64 dt=t0?(h4_qpc_now()-t0):0; (CALLS)++; if(dt>0)(TICKS)+=dt; } \
    return r; \
}
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3ba29a0_profile, g_h4_v2b0_r3ba29a0_orig, g_h4_v2b0_r3ba29a0_calls, g_h4_v2b0_r3ba29a0_ticks)
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3b87e20_profile, g_h4_v2b0_r3b87e20_orig, g_h4_v2b0_r3b87e20_calls, g_h4_v2b0_r3b87e20_ticks)
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3b8ade0_profile, g_h4_v2b0_r3b8ade0_orig, g_h4_v2b0_r3b8ade0_calls, g_h4_v2b0_r3b8ade0_ticks)
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3b895c0_profile, g_h4_v2b0_r3b895c0_orig, g_h4_v2b0_r3b895c0_calls, g_h4_v2b0_r3b895c0_ticks)
extern "C" u64 PCL_MS_ABI pcl_h4_v2b0_r3b9bab0_profile(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) {
    const bool p=h4_v2b0_child_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    if(p){ g_h4_v2b0_child_depth++; g_h4_bab0_context++; }
    const u64 r=g_h4_v2b0_r3b9bab0_orig?g_h4_v2b0_r3b9bab0_orig(a1,a2,a3,a4,a5,a6):0;
    if(p){ g_h4_bab0_context--; g_h4_v2b0_child_depth--; const i64 dt=t0?(h4_qpc_now()-t0):0; g_h4_v2b0_r3b9bab0_calls++; if(dt>0)g_h4_v2b0_r3b9bab0_ticks+=dt; }
    return r;
}
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3ba2790_profile, g_h4_v2b0_r3ba2790_orig, g_h4_v2b0_r3ba2790_calls, g_h4_v2b0_r3ba2790_ticks)
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3b8b430_profile, g_h4_v2b0_r3b8b430_orig, g_h4_v2b0_r3b8b430_calls, g_h4_v2b0_r3b8b430_ticks)
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r13ef490_profile, g_h4_v2b0_r13ef490_orig, g_h4_v2b0_r13ef490_calls, g_h4_v2b0_r13ef490_ticks)
H4_V2B0_CHILD_WRAPPER(pcl_h4_v2b0_r3b9a3d0_profile, g_h4_v2b0_r3b9a3d0_orig, g_h4_v2b0_r3b9a3d0_calls, g_h4_v2b0_r3b9a3d0_ticks)
#undef H4_V2B0_CHILD_WRAPPER

static i64 h4_v2b0_child_restore(u64 base) {
    const u8 a[18]={0x48,0x8B,0xC4,0x4C,0x89,0x40,0x18,0x48,0x89,0x50,0x10,0x48,0x81,0xEC,0xC8,0x00,0x00,0x00};
    const u8 b[15]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7C,0x24,0x20};
    const u8 c[13]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x49,0x70};
    const u8 d[12]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0xC2};
    const u8 e[13]={0x40,0x53,0x48,0x83,0xEC,0x30,0x0F,0xB6,0x81,0x00,0x01,0x00,0x00};
    const u8 f[15]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x48,0x89,0x7C,0x24,0x18};
    const u8 g[13]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x83,0xC1,0x78};
    const u8 h[13]={0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,0xEC,0x20,0x48,0x8B,0xDA};
    const u8 i[15]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20};
    bool ok=true;
    ok &= h4_nested_restore_one(base+0x03B9A3D0ull,i,15,g_h4_v2b0_r3b9a3d0_saved,(u64)&pcl_h4_v2b0_r3b9a3d0_profile);
    ok &= h4_nested_restore_one(base+0x013EF490ull,h,13,g_h4_v2b0_r13ef490_saved,(u64)&pcl_h4_v2b0_r13ef490_profile);
    ok &= h4_nested_restore_one(base+0x03B8B430ull,g,13,g_h4_v2b0_r3b8b430_saved,(u64)&pcl_h4_v2b0_r3b8b430_profile);
    ok &= h4_nested_restore_one(base+0x03BA2790ull,f,15,g_h4_v2b0_r3ba2790_saved,(u64)&pcl_h4_v2b0_r3ba2790_profile);
    ok &= h4_nested_restore_one(base+0x03B9BAB0ull,e,13,g_h4_v2b0_r3b9bab0_saved,(u64)&pcl_h4_v2b0_r3b9bab0_profile);
    ok &= h4_nested_restore_one(base+0x03B895C0ull,d,12,g_h4_v2b0_r3b895c0_saved,(u64)&pcl_h4_v2b0_r3b895c0_profile);
    ok &= h4_nested_restore_one(base+0x03B8ADE0ull,c,13,g_h4_v2b0_r3b8ade0_saved,(u64)&pcl_h4_v2b0_r3b8ade0_profile);
    ok &= h4_nested_restore_one(base+0x03B87E20ull,b,15,g_h4_v2b0_r3b87e20_saved,(u64)&pcl_h4_v2b0_r3b87e20_profile);
    ok &= h4_nested_restore_one(base+0x03BA29A0ull,a,18,g_h4_v2b0_r3ba29a0_saved,(u64)&pcl_h4_v2b0_r3ba29a0_profile);
    g_h4_v2b0_child_stock_restored=ok?1:0;
    if(ok){g_h4_v2b0_child_active=0; return 1;}
    return -528;
}

static i64 h4_v2b0_child_install(u64 base) {
    if(g_h4_v2b0_child_active) return -501;
    if(!h4_resolve_patch_api()) return -502;
    const u8 a[18]={0x48,0x8B,0xC4,0x4C,0x89,0x40,0x18,0x48,0x89,0x50,0x10,0x48,0x81,0xEC,0xC8,0x00,0x00,0x00};
    const u8 b[15]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7C,0x24,0x20};
    const u8 c[13]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x49,0x70};
    const u8 d[12]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0xC2};
    const u8 e[13]={0x40,0x53,0x48,0x83,0xEC,0x30,0x0F,0xB6,0x81,0x00,0x01,0x00,0x00};
    const u8 f[15]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x48,0x89,0x7C,0x24,0x18};
    const u8 g[13]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0xD9,0x48,0x83,0xC1,0x78};
    const u8 h[13]={0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,0xEC,0x20,0x48,0x8B,0xDA};
    const u8 i[15]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20};
    if(!h4_nested_patch_one(base+0x03BA29A0ull,a,18,g_h4_v2b0_r3ba29a0_saved,g_h4_v2b0_r3ba29a0_tramp,(u64)&pcl_h4_v2b0_r3ba29a0_profile)) return -503;
    g_h4_v2b0_r3ba29a0_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3ba29a0_tramp;
    if(!h4_nested_patch_one(base+0x03B87E20ull,b,15,g_h4_v2b0_r3b87e20_saved,g_h4_v2b0_r3b87e20_tramp,(u64)&pcl_h4_v2b0_r3b87e20_profile)){h4_v2b0_child_restore(base);return -504;} g_h4_v2b0_r3b87e20_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3b87e20_tramp;
    if(!h4_nested_patch_one(base+0x03B8ADE0ull,c,13,g_h4_v2b0_r3b8ade0_saved,g_h4_v2b0_r3b8ade0_tramp,(u64)&pcl_h4_v2b0_r3b8ade0_profile)){h4_v2b0_child_restore(base);return -505;} g_h4_v2b0_r3b8ade0_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3b8ade0_tramp;
    if(!h4_nested_patch_one(base+0x03B895C0ull,d,12,g_h4_v2b0_r3b895c0_saved,g_h4_v2b0_r3b895c0_tramp,(u64)&pcl_h4_v2b0_r3b895c0_profile)){h4_v2b0_child_restore(base);return -506;} g_h4_v2b0_r3b895c0_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3b895c0_tramp;
    if(!h4_nested_patch_one(base+0x03B9BAB0ull,e,13,g_h4_v2b0_r3b9bab0_saved,g_h4_v2b0_r3b9bab0_tramp,(u64)&pcl_h4_v2b0_r3b9bab0_profile)){h4_v2b0_child_restore(base);return -507;} g_h4_v2b0_r3b9bab0_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3b9bab0_tramp;
    if(!h4_nested_patch_one(base+0x03BA2790ull,f,15,g_h4_v2b0_r3ba2790_saved,g_h4_v2b0_r3ba2790_tramp,(u64)&pcl_h4_v2b0_r3ba2790_profile)){h4_v2b0_child_restore(base);return -508;} g_h4_v2b0_r3ba2790_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3ba2790_tramp;
    if(!h4_nested_patch_one(base+0x03B8B430ull,g,13,g_h4_v2b0_r3b8b430_saved,g_h4_v2b0_r3b8b430_tramp,(u64)&pcl_h4_v2b0_r3b8b430_profile)){h4_v2b0_child_restore(base);return -509;} g_h4_v2b0_r3b8b430_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3b8b430_tramp;
    if(!h4_nested_patch_one(base+0x013EF490ull,h,13,g_h4_v2b0_r13ef490_saved,g_h4_v2b0_r13ef490_tramp,(u64)&pcl_h4_v2b0_r13ef490_profile)){h4_v2b0_child_restore(base);return -510;} g_h4_v2b0_r13ef490_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r13ef490_tramp;
    if(!h4_nested_patch_one(base+0x03B9A3D0ull,i,15,g_h4_v2b0_r3b9a3d0_saved,g_h4_v2b0_r3b9a3d0_tramp,(u64)&pcl_h4_v2b0_r3b9a3d0_profile)){h4_v2b0_child_restore(base);return -511;} g_h4_v2b0_r3b9a3d0_orig=(H4UpdateAny6Fn)(void*)g_h4_v2b0_r3b9a3d0_tramp;
    g_h4_v2b0_child_active=1; g_h4_v2b0_child_stock_restored=0; return 1;
}

// ---------------------------------------------------------------------------
// 15.11.89: direct-child timing inside hotspot 0x3B9BAB0. The parent wrapper
// above owns g_h4_bab0_context. First-level exclusivity prevents allocator or
// helper calls nested inside another profiled BAB0 child from being double-counted.
static inline bool h4_bab0_child_should_profile() {
    return g_h4_bab0_context > 0 && g_h4_bab0_child_depth == 0 &&
           g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();
}
#define H4_BAB0_CHILD_WRAPPER(NAME, ORIG, CALLS, TICKS) \
extern "C" u64 PCL_MS_ABI NAME(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) { \
    const bool p=h4_bab0_child_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0; \
    if(p) g_h4_bab0_child_depth++; \
    const u64 r=(ORIG)?(ORIG)(a1,a2,a3,a4,a5,a6):0; \
    if(p){ g_h4_bab0_child_depth--; const i64 dt=t0?(h4_qpc_now()-t0):0; (CALLS)++; if(dt>0)(TICKS)+=dt; } \
    return r; \
}
H4_BAB0_CHILD_WRAPPER(pcl_h4_bab0_r3b8c990_profile, g_h4_bab0_r3b8c990_orig, g_h4_bab0_r3b8c990_calls, g_h4_bab0_r3b8c990_ticks)
extern "C" u64 PCL_MS_ABI pcl_h4_bab0_r3b98d20_profile(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) {
    const bool p=h4_bab0_child_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    if(p){ g_h4_bab0_child_depth++; g_h4_d20_context++; }
    const u64 r=g_h4_bab0_r3b98d20_orig?g_h4_bab0_r3b98d20_orig(a1,a2,a3,a4,a5,a6):0;
    if(p){ g_h4_d20_context--; g_h4_bab0_child_depth--; const i64 dt=t0?(h4_qpc_now()-t0):0; g_h4_bab0_r3b98d20_calls++; if(dt>0)g_h4_bab0_r3b98d20_ticks+=dt; }
    return r;
}
H4_BAB0_CHILD_WRAPPER(pcl_h4_bab0_r3ba15b0_profile, g_h4_bab0_r3ba15b0_orig, g_h4_bab0_r3ba15b0_calls, g_h4_bab0_r3ba15b0_ticks)
H4_BAB0_CHILD_WRAPPER(pcl_h4_bab0_r10d1a90_profile, g_h4_bab0_r10d1a90_orig, g_h4_bab0_r10d1a90_calls, g_h4_bab0_r10d1a90_ticks)
#undef H4_BAB0_CHILD_WRAPPER

static i64 h4_bab0_child_restore(u64 base) {
    const u8 a[15]={0x48,0x8B,0xC4,0x44,0x88,0x48,0x20,0x55,0x56,0x41,0x55,0x41,0x56,0x41,0x57};
    const u8 b[13]={0x48,0x8B,0xC4,0x48,0x89,0x48,0x08,0x55,0x56,0x41,0x54,0x41,0x55};
    const u8 c[14]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x56,0x57,0x41,0x55};
    const u8 d[20]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xEC,0x30};
    bool ok=true;
    ok &= h4_nested_restore_one(base+0x010D1A90ull,d,20,g_h4_bab0_r10d1a90_saved,(u64)&pcl_h4_bab0_r10d1a90_profile);
    ok &= h4_nested_restore_one(base+0x03BA15B0ull,c,14,g_h4_bab0_r3ba15b0_saved,(u64)&pcl_h4_bab0_r3ba15b0_profile);
    ok &= h4_nested_restore_one(base+0x03B98D20ull,b,13,g_h4_bab0_r3b98d20_saved,(u64)&pcl_h4_bab0_r3b98d20_profile);
    ok &= h4_nested_restore_one(base+0x03B8C990ull,a,15,g_h4_bab0_r3b8c990_saved,(u64)&pcl_h4_bab0_r3b8c990_profile);
    g_h4_bab0_child_stock_restored=ok?1:0;
    if(ok){g_h4_bab0_child_active=0;return 1;}
    return -548;
}

static i64 h4_bab0_child_install(u64 base) {
    if(g_h4_bab0_child_active) return -541;
    if(!h4_resolve_patch_api()) return -542;
    const u8 a[15]={0x48,0x8B,0xC4,0x44,0x88,0x48,0x20,0x55,0x56,0x41,0x55,0x41,0x56,0x41,0x57};
    const u8 b[13]={0x48,0x8B,0xC4,0x48,0x89,0x48,0x08,0x55,0x56,0x41,0x54,0x41,0x55};
    const u8 c[14]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,0x24,0x18,0x56,0x57,0x41,0x55};
    const u8 d[20]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xEC,0x30};
    if(!h4_nested_patch_one(base+0x03B8C990ull,a,15,g_h4_bab0_r3b8c990_saved,g_h4_bab0_r3b8c990_tramp,(u64)&pcl_h4_bab0_r3b8c990_profile)) return -543;
    g_h4_bab0_r3b8c990_orig=(H4UpdateAny6Fn)(void*)g_h4_bab0_r3b8c990_tramp;
    if(!h4_nested_patch_one(base+0x03B98D20ull,b,13,g_h4_bab0_r3b98d20_saved,g_h4_bab0_r3b98d20_tramp,(u64)&pcl_h4_bab0_r3b98d20_profile)){h4_bab0_child_restore(base);return -544;} g_h4_bab0_r3b98d20_orig=(H4UpdateAny6Fn)(void*)g_h4_bab0_r3b98d20_tramp;
    if(!h4_nested_patch_one(base+0x03BA15B0ull,c,14,g_h4_bab0_r3ba15b0_saved,g_h4_bab0_r3ba15b0_tramp,(u64)&pcl_h4_bab0_r3ba15b0_profile)){h4_bab0_child_restore(base);return -545;} g_h4_bab0_r3ba15b0_orig=(H4UpdateAny6Fn)(void*)g_h4_bab0_r3ba15b0_tramp;
    if(!h4_nested_patch_one(base+0x010D1A90ull,d,20,g_h4_bab0_r10d1a90_saved,g_h4_bab0_r10d1a90_tramp,(u64)&pcl_h4_bab0_r10d1a90_profile)){h4_bab0_child_restore(base);return -546;} g_h4_bab0_r10d1a90_orig=(H4UpdateAny6Fn)(void*)g_h4_bab0_r10d1a90_tramp;
    g_h4_bab0_child_active=1; g_h4_bab0_child_stock_restored=0; return 1;
}


// ---------------------------------------------------------------------------
// 15.11.90: direct-child timing inside hotspot 0x3B98D20.
// Import-thunk memcpy (0x46649A64), raw free (0x11531C0), and the already-owned
// 0x10D1A90 site are deliberately not detoured here. Their cost remains residual.
static inline bool h4_d20_child_should_profile() {
    return g_h4_d20_context > 0 && g_h4_d20_child_depth == 0 &&
           g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();
}
#define H4_D20_CHILD_WRAPPER(NAME, ORIG, CALLS, TICKS) \
extern "C" u64 PCL_MS_ABI NAME(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) { \
    const bool p=h4_d20_child_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0; \
    if(p) g_h4_d20_child_depth++; \
    const u64 r=(ORIG)?(ORIG)(a1,a2,a3,a4,a5,a6):0; \
    if(p){ g_h4_d20_child_depth--; const i64 dt=t0?(h4_qpc_now()-t0):0; (CALLS)++; if(dt>0)(TICKS)+=dt; } \
    return r; \
}
H4_D20_CHILD_WRAPPER(pcl_h4_d20_r10d0f20_profile, g_h4_d20_r10d0f20_orig, g_h4_d20_r10d0f20_calls, g_h4_d20_r10d0f20_ticks)
extern "C" u64 PCL_MS_ABI pcl_h4_d20_r3b99a20_profile(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) {
    const bool p = h4_d20_child_should_profile();
    H4SourceEntry* e = p ? g_h4_current_scope_entry : 0;
    const u32 state_before = e ? e->a20_state : 0u;
    const u32 geometry_before = e ? e->geometry_state : 0u;

    bool planned_fast = false;
    bool planned_canary = false;
    if (p && e && state_before == 2u && geometry_before == 2u && e->a20_reserved == 1u && g_h4_a20_resize) {
        if (e->a20_since_canary + 1u >= H4_A20_CANARY_INTERVAL) {
            e->a20_since_canary = 0;
            planned_canary = true;
            g_h4_a20_canary_calls++;
        } else {
            e->a20_since_canary++;
            planned_fast = true;
        }
    }

    const i64 t0 = p && g_h4_qpf > 0 ? h4_qpc_now() : 0;
    if (p) g_h4_d20_child_depth++;
    u64 r = 0;
    bool used_fast = false;
    if (planned_fast) {
        const i64 ct0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
        used_fast = h4_a20_apply_cache(e,a1,a2,a3,a4);
        const i64 cdt = ct0 ? (h4_qpc_now()-ct0) : 0;
        if (used_fast) {
            g_h4_a20_cache_fast_calls++;
            g_h4_a20_cache_fast_bytes += (i64)(e->a20_cache_bytes0+e->a20_cache_bytes1+e->a20_cache_bytes2+e->a20_cache_bytes3);
            if (cdt > 0) g_h4_a20_cache_copy_ticks += cdt;
        } else {
            g_h4_a20_cache_apply_fail++;
            g_h4_a20_cache_fallback_calls++;
            e->a20_state = 3u;
            e->a20_reserved = 0u;
            g_h4_a20_late_demotions++;
        }
    }
    if (!used_fast) {
        r = g_h4_d20_r3b99a20_orig ? g_h4_d20_r3b99a20_orig(a1,a2,a3,a4,a5,a6) : 0;
    }
    if (p) {
        g_h4_d20_child_depth--;
        const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
        g_h4_d20_r3b99a20_calls++;
        if (dt > 0) g_h4_d20_r3b99a20_ticks += dt;

        if (e && state_before == 2u && geometry_before == 2u) {
            g_h4_a20_candidate_calls++;
            if (dt > 0) g_h4_a20_candidate_ticks += dt;
        } else if (e && (state_before == 3u || geometry_before == 3u)) {
            g_h4_a20_blocked_calls++;
            if (dt > 0) g_h4_a20_blocked_ticks += dt;
        } else {
            g_h4_a20_proving_calls++;
            if (dt > 0) g_h4_a20_proving_ticks += dt;
        }

        // Fast calls already reproduced the proven four arrays and do not need hashing.
        // Stock proof/canary calls continue to validate the cache against real A20 output.
        bool check = false;
        bool canary = planned_canary;
        if (!used_fast && e && e->a20_state != 3u) {
            if (e->a20_state == 0u || e->a20_state == 1u) check = true;
            else if (e->a20_state == 2u && planned_canary) check = true;
        }
        if (check) {
            u64 h0=0,h1=0,h2=0,h3=0,b0=0,b1=0,b2=0,b3=0;
            u32 n0=0,n1=0,n2=0,n3=0;
            const i64 ht0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
            const bool ok0 = h4_capture_tarray_stride(a1,12u,&h0,&n0,&b0);
            const bool ok1 = h4_capture_int_tarray(a2,&h1,&n1,&b1);
            const bool ok2 = h4_capture_int_tarray(a3,&h2,&n2,&b2);
            const bool ok3 = h4_capture_int_tarray(a4,&h3,&n3,&b3);
            const i64 hdt = ht0 ? (h4_qpc_now()-ht0) : 0;
            if (hdt > 0) g_h4_a20_hash_ticks += hdt;
            g_h4_a20_checks++;
            if (!ok0 || !ok1 || !ok2 || !ok3) {
                g_h4_a20_guard_fail++;
                if (e->a20_state == 2u) g_h4_a20_late_demotions++; else g_h4_a20_rejected_sources++;
                e->a20_state = 3u; e->a20_reserved = 0u;
            } else {
                g_h4_a20_output0_bytes += (i64)b0;
                g_h4_a20_output1_bytes += (i64)b1;
                g_h4_a20_output2_bytes += (i64)b2;
                g_h4_a20_output3_bytes += (i64)b3;
                if (e->a20_state == 0u) {
                    e->a20_hash0=h0; e->a20_hash1=h1; e->a20_hash2=h2; e->a20_hash3=h3;
                    e->a20_num0=n0; e->a20_num1=n1; e->a20_num2=n2; e->a20_num3=n3;
                    e->a20_matches=1u; e->a20_state=1u;
                } else {
                    u32 mismatch=0;
                    if (e->a20_num0 != n0) mismatch |= 1u;
                    if (e->a20_hash0 != h0) mismatch |= 2u;
                    if (e->a20_num1 != n1) mismatch |= 4u;
                    if (e->a20_hash1 != h1) mismatch |= 8u;
                    if (e->a20_num2 != n2) mismatch |= 16u;
                    if (e->a20_hash2 != h2) mismatch |= 32u;
                    if (e->a20_num3 != n3) mismatch |= 64u;
                    if (e->a20_hash3 != h3) mismatch |= 128u;
                    if (mismatch) {
                        if (!g_h4_a20_first_mismatch_source) { g_h4_a20_first_mismatch_source=e->source; g_h4_a20_first_mismatch_code=mismatch; }
                        if (e->a20_state == 2u) {
                            g_h4_a20_late_demotions++;
                            if (canary) g_h4_a20_canary_mismatch++;
                        } else g_h4_a20_rejected_sources++;
                        e->a20_state=3u; e->a20_reserved=0u;
                    } else if (e->a20_state == 1u) {
                        e->a20_matches++;
                        if (e->a20_matches >= H4_A20_PROOF_MATCHES) {
                            e->a20_state=2u; e->a20_since_canary=0;
                            g_h4_a20_promoted_sources++;
                            h4_a20_capture_cache(e,a1,a2,a3,a4,b0,b1,b2,b3);
                        }
                    }
                }
            }
        }
    }
    return r;
}
H4_D20_CHILD_WRAPPER(pcl_h4_d20_r1a297f0_profile, g_h4_d20_r1a297f0_orig, g_h4_d20_r1a297f0_calls, g_h4_d20_r1a297f0_ticks)
extern "C" u64 PCL_MS_ABI pcl_h4_d20_r3b7acf0_profile(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) {
    const bool p=h4_d20_child_should_profile();
    const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    if(p){ g_h4_d20_child_depth++; g_h4_acf0_context++; }
    const u64 r=g_h4_d20_r3b7acf0_orig?g_h4_d20_r3b7acf0_orig(a1,a2,a3,a4,a5,a6):0;
    if(p){
        g_h4_acf0_context--;
        g_h4_d20_child_depth--;
        const i64 dt=t0?(h4_qpc_now()-t0):0;
        g_h4_d20_r3b7acf0_calls++;
        if(dt>0) g_h4_d20_r3b7acf0_ticks+=dt;
    }
    return r;
}
H4_D20_CHILD_WRAPPER(pcl_h4_d20_r3b7b3a0_profile, g_h4_d20_r3b7b3a0_orig, g_h4_d20_r3b7b3a0_calls, g_h4_d20_r3b7b3a0_ticks)
#undef H4_D20_CHILD_WRAPPER


static inline bool h4_f490_should_profile() {
    return g_h4_acf0_context > 0 && g_h4_f490_depth == 0 &&
           g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();
}

extern "C" int PCL_MS_ABI h4_f490_mid_try_fast(void* object_ptr) {
    H4SourceEntry* e = g_h4_f490_fast_entry;
    const u64 obj = (u64)object_ptr;
    if (!e || e->f490_state != 2u || e->geometry_state != 2u || e->f490_reserved != 1u) return 0;
    if (obj < 0x10000ull || obj != g_h4_f490_fast_object) { g_h4_f490_mid_guard_fail++; return 0; }
    if (g_h4_scope_owner_teb == 0 || g_h4_scope_owner_teb != get_teb()) { g_h4_f490_mid_guard_fail++; return 0; }
    const i64 t0 = g_h4_qpf > 0 ? h4_qpc_now() : 0;
    h4_copy_bytes(obj + 0x88ull, (u64)&e->f490_bounds_cache[0], 0x30ull);
    const i64 dt = t0 ? (h4_qpc_now()-t0) : 0;
    g_h4_f490_fast_calls++;
    g_h4_f490_fast_bytes += 0x30;
    if (dt > 0) g_h4_f490_fast_copy_ticks += dt;
    return 1;
}

static bool h4_f490_build_mid_dispatch(u64 fast_cont) {
    ULONG old_dispatch = 0;
    if (!h4_protect_rwx(g_h4_f490_mid_dispatch, sizeof(g_h4_f490_mid_dispatch), &old_dispatch)) return false;
    u8* p = g_h4_f490_mid_dispatch;
    h4_emit_u8(p,0x51); h4_emit_u8(p,0x52);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x50);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x51);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x52);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x53);
    h4_emit_u8(p,0x48); h4_emit_u8(p,0x83); h4_emit_u8(p,0xEC); h4_emit_u8(p,0x20);
    // RCX = R14, F490's object pointer at RVA 0x1CFF5E9.
    h4_emit_u8(p,0x4C); h4_emit_u8(p,0x89); h4_emit_u8(p,0xF1);
    h4_emit_u8(p,0x48); h4_emit_u8(p,0xB8); h4_emit_u64(p,(u64)&h4_f490_mid_try_fast);
    h4_emit_u8(p,0xFF); h4_emit_u8(p,0xD0);
    h4_emit_u8(p,0x48); h4_emit_u8(p,0x83); h4_emit_u8(p,0xC4); h4_emit_u8(p,0x20);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x5B);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x5A);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x59);
    h4_emit_u8(p,0x41); h4_emit_u8(p,0x58);
    h4_emit_u8(p,0x5A); h4_emit_u8(p,0x59);
    h4_emit_u8(p,0x85); h4_emit_u8(p,0xC0);
    h4_emit_u8(p,0x75); h4_emit_u8(p,0x0E);
    h4_emit_abs_jump(p,(u64)g_h4_f490_mid_tramp); p += 14;
    h4_emit_abs_jump(p,fast_cont); p += 14;
    while ((u64)(p-g_h4_f490_mid_dispatch) < sizeof(g_h4_f490_mid_dispatch)) *p++=0xCC;
    h4_flush_code(g_h4_f490_mid_dispatch,(ULONG)sizeof(g_h4_f490_mid_dispatch));
    (void)old_dispatch;
    return true;
}

static i64 h4_f490_mid_install(u64 base) {
    if (g_h4_f490_mid_active) return -611;
    if (!h4_resolve_patch_api()) return -612;
    const u64 target=base+0x01CFF5E9ull;
    const u64 fast_cont=base+0x01CFF98Cull;
    const u8 sig[16]={0x49,0x8B,0x56,0x70,0x0F,0x29,0x74,0x24,0x50,0x0F,0xB7,0x02,0x48,0x8D,0x0C,0x40};
    if(!h4_bytes_match(target,sig,16)) return -613;
    ULONG old_tramp=0,old_target=0;
    if(!h4_protect_rwx(g_h4_f490_mid_tramp,sizeof(g_h4_f490_mid_tramp),&old_tramp)) return -614;
    if(!h4_protect_rwx((void*)target,16,&old_target)){ h4_restore_protection(g_h4_f490_mid_tramp,sizeof(g_h4_f490_mid_tramp),old_tramp); return -615; }
    for(u32 i=0;i<16u;++i){ const u8 b=rd<u8>(target+i); g_h4_f490_mid_saved[i]=b; g_h4_f490_mid_tramp[i]=b; }
    h4_emit_abs_jump(g_h4_f490_mid_tramp+16,target+16);
    for(u32 i=30;i<sizeof(g_h4_f490_mid_tramp);++i) g_h4_f490_mid_tramp[i]=0xCC;
    h4_flush_code(g_h4_f490_mid_tramp,(ULONG)sizeof(g_h4_f490_mid_tramp));
    if(!h4_f490_build_mid_dispatch(fast_cont)){ h4_restore_protection((void*)target,16,old_target); return -616; }
    u8 patch[16]; for(u32 i=0;i<16u;++i) patch[i]=0x90;
    h4_emit_abs_jump(patch,(u64)g_h4_f490_mid_dispatch);
    for(u32 i=0;i<16u;++i) wr<u8>(target+i,patch[i]);
    h4_flush_code((void*)target,16); h4_restore_protection((void*)target,16,old_target);
    (void)old_tramp;
    g_h4_f490_mid_fast_cont=fast_cont; g_h4_f490_mid_active=1; g_h4_f490_mid_stock_restored=0;
    return 1;
}

static i64 h4_f490_mid_restore(u64 base) {
    const u64 target=base+0x01CFF5E9ull;
    const u8 sig[16]={0x49,0x8B,0x56,0x70,0x0F,0x29,0x74,0x24,0x50,0x0F,0xB7,0x02,0x48,0x8D,0x0C,0x40};
    if(!g_h4_f490_mid_active){ g_h4_f490_mid_stock_restored=h4_bytes_match(target,sig,16)?1:0; return g_h4_f490_mid_stock_restored?0:-621; }
    const u8 pref[6]={0xFF,0x25,0,0,0,0};
    if(!h4_bytes_match(target,pref,6) || rd<u64>(target+6)!=(u64)g_h4_f490_mid_dispatch){ g_h4_f490_mid_stock_restored=0; return -622; }
    ULONG old_target=0; if(!h4_protect_rwx((void*)target,16,&old_target)){g_h4_f490_mid_stock_restored=0;return -623;}
    for(u32 i=0;i<16u;++i) wr<u8>(target+i,g_h4_f490_mid_saved[i]);
    h4_flush_code((void*)target,16); h4_restore_protection((void*)target,16,old_target);
    g_h4_f490_mid_stock_restored=h4_bytes_match(target,sig,16)?1:0;
    if(g_h4_f490_mid_stock_restored){g_h4_f490_mid_active=0;g_h4_f490_mid_fast_cont=0;return 1;}
    return -624;
}


extern "C" void PCL_MS_ABI pcl_h4_f490_finalizer_call(void* object_ptr) {
    H4F490FinalizerFn orig = g_h4_f490_finalizer_orig;
    if (!orig) { g_h4_f490_finalizer_guard_fail++; return; }
    const bool p = g_h4_acf0_context > 0 && g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();
    const i64 t0 = p && g_h4_qpf > 0 ? h4_qpc_now() : 0;
    orig(object_ptr);
    if (p) {
        const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
        g_h4_f490_finalizer_calls++;
        if (dt > 0) g_h4_f490_finalizer_ticks += dt;
    }
}

static void h4_f490_finalizer_make_patch(u8* patch) {
    // FF 15 12 00 00 00        call qword ptr [rip+0x12] ; qword at +24
    // 48 8B AC 24 88 00 00 00 mov rbp,[rsp+0x88]
    // 49 8B C6                 mov rax,r14
    // 48 83 C4 60              add rsp,0x60
    // 41 5E                    pop r14
    // C3                       ret
    // dq pcl_h4_f490_finalizer_call
    const u8 head[24] = {
        0xFF,0x15,0x12,0x00,0x00,0x00,
        0x48,0x8B,0xAC,0x24,0x88,0x00,0x00,0x00,
        0x49,0x8B,0xC6,
        0x48,0x83,0xC4,0x60,
        0x41,0x5E,
        0xC3
    };
    for (u32 i=0;i<24u;++i) patch[i]=head[i];
    *(u64*)(patch+24)=(u64)&pcl_h4_f490_finalizer_call;
}

static i64 h4_f490_finalizer_install(u64 base) {
    if (g_h4_f490_finalizer_active) return -631;
    if (!h4_resolve_patch_api()) return -632;
    const u64 target = base + 0x01CFF98Full;
    const u8 sig[32] = {
        0xE8,0x5C,0x68,0x03,0x00,
        0x48,0x8B,0xAC,0x24,0x88,0x00,0x00,0x00,
        0x49,0x8B,0xC6,
        0x48,0x83,0xC4,0x60,
        0x41,0x5E,
        0xC3,
        0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC
    };
    if (!h4_bytes_match(target,sig,32)) return -633;
    for (u32 i=0;i<32u;++i) g_h4_f490_finalizer_saved[i]=rd<u8>(target+i);
    g_h4_f490_finalizer_orig=(H4F490FinalizerFn)(base+0x01D361F0ull);
    u8 patch[32]; h4_f490_finalizer_make_patch(patch);
    ULONG old=0; if(!h4_protect_rwx((void*)target,32,&old)) return -634;
    for(u32 i=0;i<32u;++i) wr<u8>(target+i,patch[i]);
    h4_flush_code((void*)target,32); h4_restore_protection((void*)target,32,old);
    if(!h4_bytes_match(target,patch,32)) return -635;
    g_h4_f490_finalizer_active=1; g_h4_f490_finalizer_stock_restored=0;
    return 1;
}

static i64 h4_f490_finalizer_restore(u64 base) {
    const u64 target = base + 0x01CFF98Full;
    const u8 sig[32] = {
        0xE8,0x5C,0x68,0x03,0x00,
        0x48,0x8B,0xAC,0x24,0x88,0x00,0x00,0x00,
        0x49,0x8B,0xC6,
        0x48,0x83,0xC4,0x60,
        0x41,0x5E,
        0xC3,
        0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC,0xCC
    };
    if(!g_h4_f490_finalizer_active){
        g_h4_f490_finalizer_stock_restored=h4_bytes_match(target,sig,32)?1:0;
        return g_h4_f490_finalizer_stock_restored?0:-641;
    }
    u8 patch[32]; h4_f490_finalizer_make_patch(patch);
    if(!h4_bytes_match(target,patch,32)){ g_h4_f490_finalizer_stock_restored=0; return -642; }
    ULONG old=0; if(!h4_protect_rwx((void*)target,32,&old)){g_h4_f490_finalizer_stock_restored=0;return -643;}
    for(u32 i=0;i<32u;++i) wr<u8>(target+i,g_h4_f490_finalizer_saved[i]);
    h4_flush_code((void*)target,32); h4_restore_protection((void*)target,32,old);
    g_h4_f490_finalizer_stock_restored=h4_bytes_match(target,sig,32)?1:0;
    if(g_h4_f490_finalizer_stock_restored){g_h4_f490_finalizer_active=0;return 1;}
    return -644;
}


extern "C" void PCL_MS_ABI pcl_h4_f490_tail_bundle_call(void* object_ptr, void* temp_ptr) {
    H4F490TailBuildFn build = g_h4_f490_tail_build_orig;
    H4F490TailCleanupFn cleanup = g_h4_f490_tail_cleanup_orig;
    if (!build || !cleanup) { g_h4_f490_tail_guard_fail++; return; }
    const bool p = g_h4_acf0_context > 0 && g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();

    const i64 t0 = p && g_h4_qpf > 0 ? h4_qpc_now() : 0;
    build(object_ptr, temp_ptr);
    if (p) {
        const i64 dt = t0 ? (h4_qpc_now() - t0) : 0;
        g_h4_f490_tail_build_calls++;
        if (dt > 0) g_h4_f490_tail_build_ticks += dt;
    }

    const i64 t1 = p && g_h4_qpf > 0 ? h4_qpc_now() : 0;
    cleanup(temp_ptr);
    if (p) {
        const i64 dt = t1 ? (h4_qpc_now() - t1) : 0;
        g_h4_f490_tail_cleanup_calls++;
        if (dt > 0) g_h4_f490_tail_cleanup_ticks += dt;
    }
}

static void h4_f490_tail_make_patch(u8* patch) {
    // lea rdx,[rsp+0x50]
    patch[0]=0x48; patch[1]=0x8D; patch[2]=0x54; patch[3]=0x24; patch[4]=0x50;
    // mov rcx,rdi
    patch[5]=0x48; patch[6]=0x8B; patch[7]=0xCF;
    // mov rax, imm64
    patch[8]=0x48; patch[9]=0xB8;
    *(u64*)(patch+10)=(u64)&pcl_h4_f490_tail_bundle_call;
    // call rax
    patch[18]=0xFF; patch[19]=0xD0;
    // pad exact 23-byte site
    patch[20]=0x90; patch[21]=0x90; patch[22]=0x90;
}

static i64 h4_f490_tail_install(u64 base) {
    if (g_h4_f490_tail_active) return -651;
    if (!h4_resolve_patch_api()) return -652;
    const u64 target = base + 0x01D363D0ull;
    const u8 sig[23] = {
        0x48,0x8D,0x54,0x24,0x50,
        0x48,0x8B,0xCF,
        0xE8,0x43,0x00,0x00,0x00,
        0x48,0x8D,0x4C,0x24,0x50,
        0xE8,0xC9,0x9A,0xFF,0xFF
    };
    if (!h4_bytes_match(target,sig,23)) return -653;
    for (u32 i=0;i<23u;++i) g_h4_f490_tail_saved[i]=rd<u8>(target+i);
    g_h4_f490_tail_build_orig=(H4F490TailBuildFn)(base+0x01D36420ull);
    g_h4_f490_tail_cleanup_orig=(H4F490TailCleanupFn)(base+0x01D2FEB0ull);
    u8 patch[23]; h4_f490_tail_make_patch(patch);
    ULONG old=0; if(!h4_protect_rwx((void*)target,23,&old)) return -654;
    for(u32 i=0;i<23u;++i) wr<u8>(target+i,patch[i]);
    h4_flush_code((void*)target,23); h4_restore_protection((void*)target,23,old);
    if(!h4_bytes_match(target,patch,23)) return -655;
    g_h4_f490_tail_active=1; g_h4_f490_tail_stock_restored=0;
    return 1;
}

static i64 h4_f490_tail_restore(u64 base) {
    const u64 target = base + 0x01D363D0ull;
    const u8 sig[23] = {
        0x48,0x8D,0x54,0x24,0x50,
        0x48,0x8B,0xCF,
        0xE8,0x43,0x00,0x00,0x00,
        0x48,0x8D,0x4C,0x24,0x50,
        0xE8,0xC9,0x9A,0xFF,0xFF
    };
    if(!g_h4_f490_tail_active){
        g_h4_f490_tail_stock_restored=h4_bytes_match(target,sig,23)?1:0;
        return g_h4_f490_tail_stock_restored?0:-661;
    }
    u8 patch[23]; h4_f490_tail_make_patch(patch);
    if(!h4_bytes_match(target,patch,23)){ g_h4_f490_tail_stock_restored=0; return -662; }
    ULONG old=0; if(!h4_protect_rwx((void*)target,23,&old)){g_h4_f490_tail_stock_restored=0;return -663;}
    for(u32 i=0;i<23u;++i) wr<u8>(target+i,g_h4_f490_tail_saved[i]);
    h4_flush_code((void*)target,23); h4_restore_protection((void*)target,23,old);
    g_h4_f490_tail_stock_restored=h4_bytes_match(target,sig,23)?1:0;
    if(g_h4_f490_tail_stock_restored){g_h4_f490_tail_active=0;return 1;}
    return -664;
}

extern "C" u64 PCL_MS_ABI
pcl_h4_f490_profile(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) {
    const bool p = h4_f490_should_profile();
    H4SourceEntry* e = p ? g_h4_current_scope_entry : 0;
    const u32 state_before = e ? e->f490_state : 0u;
    const u32 geometry_before = e ? e->geometry_state : 0u;

    bool planned_check=false, planned_canary=false, planned_fast=false;
    if(p && e && e->f490_state!=3u){
        if(e->f490_state==0u || e->f490_state==1u) planned_check=true;
        else if(e->f490_state==2u){
            if(e->f490_since_canary+1u>=H4_F490_CANARY_INTERVAL){
                e->f490_since_canary=0u; planned_check=true; planned_canary=true; g_h4_f490_canary_calls++;
            } else {
                e->f490_since_canary++;
                if(e->geometry_state==2u && e->f490_reserved==1u && g_h4_f490_mid_active) planned_fast=true;
            }
        }
    }

    const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0;
    if(p){
        g_h4_f490_depth++;
        g_h4_f490_fast_entry = planned_fast ? e : 0;
        g_h4_f490_fast_object = planned_fast ? a1 : 0;
    }
    const i64 fast_before = g_h4_f490_fast_calls;
    const u64 r=g_h4_f490_orig?g_h4_f490_orig(a1,a2,a3,a4,a5,a6):0;
    if(p){
        g_h4_f490_fast_entry=0; g_h4_f490_fast_object=0;
        g_h4_f490_depth--;
        if(planned_fast && g_h4_f490_fast_calls==fast_before) g_h4_f490_fast_misses++;
        const i64 dt=t0?(h4_qpc_now()-t0):0;
        g_h4_f490_calls++; if(dt>0) g_h4_f490_ticks+=dt;
        if(e && state_before==2u && geometry_before==2u){g_h4_f490_candidate_calls++;if(dt>0)g_h4_f490_candidate_ticks+=dt;}
        else if(e && (state_before==3u || geometry_before==3u)){g_h4_f490_blocked_calls++;if(dt>0)g_h4_f490_blocked_ticks+=dt;}
        else {g_h4_f490_proving_calls++;if(dt>0)g_h4_f490_proving_ticks+=dt;}

        if(planned_check && e){
            g_h4_f490_checks++;
            if(a1<0x10000ull || (r!=0 && r!=a1)){
                g_h4_f490_guard_fail++;
                if(e->f490_state==2u) g_h4_f490_late_demotions++; else g_h4_f490_rejected_sources++;
                e->f490_state=3u; e->f490_reserved=0u;
            } else {
                const i64 ht0=g_h4_qpf>0?h4_qpc_now():0;
                const u64 h=h4_fnv1a_bytes(a1+0x88ull,0x30ull,1469598103934665603ull);
                const i64 hdt=ht0?(h4_qpc_now()-ht0):0; if(hdt>0) g_h4_f490_hash_ticks+=hdt;
                if(e->f490_state==0u){
                    e->f490_bounds_hash=h; e->f490_matches=1u; e->f490_state=1u;
                    h4_copy_bytes((u64)&e->f490_bounds_cache[0],a1+0x88ull,0x30ull); e->f490_reserved=1u;
                } else if(e->f490_bounds_hash!=h){
                    if(!g_h4_f490_first_mismatch_source){g_h4_f490_first_mismatch_source=e->source;g_h4_f490_first_mismatch_code=1u;}
                    if(e->f490_state==2u){g_h4_f490_late_demotions++;if(planned_canary)g_h4_f490_canary_mismatch++;}
                    else g_h4_f490_rejected_sources++;
                    e->f490_state=3u; e->f490_reserved=0u;
                } else if(e->f490_state==1u){
                    e->f490_matches++;
                    if(e->f490_matches>=H4_F490_PROOF_MATCHES){e->f490_state=2u;e->f490_since_canary=0u;g_h4_f490_promoted_sources++;}
                }
            }
        }
    }
    return r;
}

static i64 h4_f490_restore(u64 base) {
    const u8 sig[13]={0x48,0x8B,0xC4,0x48,0x89,0x68,0x20,0x41,0x56,0x48,0x83,0xEC,0x60};
    const bool ok = h4_nested_restore_one(base+0x01CFF490ull,sig,13,g_h4_f490_saved,(u64)&pcl_h4_f490_profile);
    g_h4_f490_stock_restored = ok ? 1 : 0;
    if (ok) { g_h4_f490_active = 0; return 1; }
    return -602;
}

static i64 h4_f490_install(u64 base) {
    if (g_h4_f490_active) return -599;
    if (!h4_resolve_patch_api()) return -600;
    const u8 sig[13]={0x48,0x8B,0xC4,0x48,0x89,0x68,0x20,0x41,0x56,0x48,0x83,0xEC,0x60};
    if (!h4_nested_patch_one(base+0x01CFF490ull,sig,13,g_h4_f490_saved,g_h4_f490_tramp,(u64)&pcl_h4_f490_profile))
        return -601;
    g_h4_f490_orig=(H4UpdateAny6Fn)(void*)g_h4_f490_tramp;
    g_h4_f490_active=1;
    g_h4_f490_stock_restored=0;
    return 1;
}

static i64 h4_d20_child_restore(u64 base) {
    const u8 a[19]={0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x41,0x54,0x41,0x56,0x48,0x83,0xEC,0x30};
    const u8 b[17]={0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x55,0x48,0x8D,0xAC,0x24,0xA8,0xFC,0xFF,0xFF};
    const u8 c[20]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7C,0x24,0x20};
    const u8 d[16]={0x40,0x55,0x41,0x56,0x41,0x57,0x48,0x81,0xEC,0xD0,0x00,0x00,0x00,0x48,0x8B,0x01};
    const u8 e[16]={0x40,0x55,0x41,0x56,0x41,0x57,0x48,0x81,0xEC,0xE0,0x00,0x00,0x00,0x48,0x8B,0x01};
    bool ok=true;
    ok &= h4_nested_restore_one(base+0x03B7B3A0ull,e,16,g_h4_d20_r3b7b3a0_saved,(u64)&pcl_h4_d20_r3b7b3a0_profile);
    ok &= h4_nested_restore_one(base+0x03B7ACF0ull,d,16,g_h4_d20_r3b7acf0_saved,(u64)&pcl_h4_d20_r3b7acf0_profile);
    ok &= h4_nested_restore_one(base+0x01A297F0ull,c,20,g_h4_d20_r1a297f0_saved,(u64)&pcl_h4_d20_r1a297f0_profile);
    ok &= h4_nested_restore_one(base+0x03B99A20ull,b,17,g_h4_d20_r3b99a20_saved,(u64)&pcl_h4_d20_r3b99a20_profile);
    ok &= h4_nested_restore_one(base+0x010D0F20ull,a,19,g_h4_d20_r10d0f20_saved,(u64)&pcl_h4_d20_r10d0f20_profile);
    g_h4_d20_child_stock_restored=ok?1:0;
    if(ok){g_h4_d20_child_active=0;return 1;}
    return -568;
}
static i64 h4_d20_child_install(u64 base) {
    if(g_h4_d20_child_active) return -561;
    if(!h4_resolve_patch_api()) return -562;
    const u8 a[19]={0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x41,0x54,0x41,0x56,0x48,0x83,0xEC,0x30};
    const u8 b[17]={0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x55,0x48,0x8D,0xAC,0x24,0xA8,0xFC,0xFF,0xFF};
    const u8 c[20]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7C,0x24,0x20};
    const u8 d[16]={0x40,0x55,0x41,0x56,0x41,0x57,0x48,0x81,0xEC,0xD0,0x00,0x00,0x00,0x48,0x8B,0x01};
    const u8 e[16]={0x40,0x55,0x41,0x56,0x41,0x57,0x48,0x81,0xEC,0xE0,0x00,0x00,0x00,0x48,0x8B,0x01};
    // 15.11.98 does not patch the resize helper. It accepts either the exact stock
    // prologue, or the exact 15-byte RIP-indirect detour shape installed by PCL's
    // older persistent-backing profiler at this same RVA. Calling the detoured entry
    // is safe for A20's 12/4-byte arrays because that wrapper only enters its special
    // alias path for stride 0x120 while armed inside Child-D; otherwise it forwards
    // directly to its stock trampoline. Any other bytes disable A20 cache reuse.
    const u64 resize_addr=base+0x010D0AB0ull;
    const u8 resize_sig[16]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57};
    const u8 pcl_detour_sig[6]={0xFF,0x25,0x00,0x00,0x00,0x00};
    if(h4_bytes_match(resize_addr,resize_sig,16)){
        g_h4_a20_resize=(H4A20ResizeFn)resize_addr;
        g_h4_a20_cache_resize_guard_ok=1; // direct stock
    } else if(h4_bytes_match(resize_addr,pcl_detour_sig,6) &&
              rd<u8>(resize_addr+14)==0x90 && rd<u8>(resize_addr+15)==0x57){
        const u64 chained_hook=rd<u64>(resize_addr+6);
        if(chained_hook>=0x10000ull && chained_hook!=~0ull){
            g_h4_a20_resize=(H4A20ResizeFn)resize_addr; // call through existing PCL detour
            g_h4_a20_cache_resize_guard_ok=2;
        } else {
            g_h4_a20_resize=0;
            g_h4_a20_cache_resize_guard_ok=0;
        }
    } else {
        g_h4_a20_resize=0;
        g_h4_a20_cache_resize_guard_ok=0;
    }
    if(!h4_nested_patch_one(base+0x010D0F20ull,a,19,g_h4_d20_r10d0f20_saved,g_h4_d20_r10d0f20_tramp,(u64)&pcl_h4_d20_r10d0f20_profile)) return -563;
    g_h4_d20_r10d0f20_orig=(H4UpdateAny6Fn)(void*)g_h4_d20_r10d0f20_tramp;
    if(!h4_nested_patch_one(base+0x03B99A20ull,b,17,g_h4_d20_r3b99a20_saved,g_h4_d20_r3b99a20_tramp,(u64)&pcl_h4_d20_r3b99a20_profile)){h4_d20_child_restore(base);return -564;} g_h4_d20_r3b99a20_orig=(H4UpdateAny6Fn)(void*)g_h4_d20_r3b99a20_tramp;
    if(!h4_nested_patch_one(base+0x01A297F0ull,c,20,g_h4_d20_r1a297f0_saved,g_h4_d20_r1a297f0_tramp,(u64)&pcl_h4_d20_r1a297f0_profile)){h4_d20_child_restore(base);return -565;} g_h4_d20_r1a297f0_orig=(H4UpdateAny6Fn)(void*)g_h4_d20_r1a297f0_tramp;
    if(!h4_nested_patch_one(base+0x03B7ACF0ull,d,16,g_h4_d20_r3b7acf0_saved,g_h4_d20_r3b7acf0_tramp,(u64)&pcl_h4_d20_r3b7acf0_profile)){h4_d20_child_restore(base);return -566;} g_h4_d20_r3b7acf0_orig=(H4UpdateAny6Fn)(void*)g_h4_d20_r3b7acf0_tramp;
    if(!h4_nested_patch_one(base+0x03B7B3A0ull,e,16,g_h4_d20_r3b7b3a0_saved,g_h4_d20_r3b7b3a0_tramp,(u64)&pcl_h4_d20_r3b7b3a0_profile)){h4_d20_child_restore(base);return -567;} g_h4_d20_r3b7b3a0_orig=(H4UpdateAny6Fn)(void*)g_h4_d20_r3b7b3a0_tramp;
    g_h4_d20_child_active=1; g_h4_d20_child_stock_restored=0; return 1;
}

// ---------------------------------------------------------------------------
// 15.11.80 retained disabled direct-callee profiling within update RVA 0x40119F0.
// These wrappers profile only the first profiled helper entered directly from the
// update helper. Any profiled helper reached from inside another profiled helper is
// suppressed by g_h4_update_direct_depth, eliminating inclusive double-counting.
static inline bool h4_update_direct_should_profile() {
    return g_h4_update_depth > 0 && g_h4_update_direct_depth == 0 &&
           g_h4_scope_owner_teb != 0 && g_h4_scope_owner_teb == get_teb();
}
#define H4_UD_WRAPPER(NAME, ORIG, CALLS, TICKS) \
extern "C" u64 PCL_MS_ABI NAME(u64 a1,u64 a2,u64 a3,u64 a4,u64 a5,u64 a6) { \
    const bool p=h4_update_direct_should_profile(); const i64 t0=p&&g_h4_qpf>0?h4_qpc_now():0; \
    if(p) g_h4_update_direct_depth++; \
    const u64 r=(ORIG)?(ORIG)(a1,a2,a3,a4,a5,a6):0; \
    if(p){ g_h4_update_direct_depth--; const i64 dt=t0?(h4_qpc_now()-t0):0; (CALLS)++; if(dt>0)(TICKS)+=dt; } \
    return r; \
}
H4_UD_WRAPPER(pcl_h4_ud_create_profile,   g_h4_ud_create_orig,   g_h4_ud_create_calls,   g_h4_ud_create_ticks)
H4_UD_WRAPPER(pcl_h4_ud_array_a_profile,  g_h4_ud_array_a_orig,  g_h4_ud_array_a_calls,  g_h4_ud_array_a_ticks)
H4_UD_WRAPPER(pcl_h4_ud_array_b_profile,  g_h4_ud_array_b_orig,  g_h4_ud_array_b_calls,  g_h4_ud_array_b_ticks)
H4_UD_WRAPPER(pcl_h4_ud_payload_profile,  g_h4_ud_payload_orig,  g_h4_ud_payload_calls,  g_h4_ud_payload_ticks)
H4_UD_WRAPPER(pcl_h4_ud_dispatch_profile, g_h4_ud_dispatch_orig, g_h4_ud_dispatch_calls, g_h4_ud_dispatch_ticks)
H4_UD_WRAPPER(pcl_h4_ud_post_profile,     g_h4_ud_post_orig,     g_h4_ud_post_calls,     g_h4_ud_post_ticks)
H4_UD_WRAPPER(pcl_h4_ud_alloc_profile,    g_h4_ud_alloc_orig,    g_h4_ud_alloc_calls,    g_h4_ud_alloc_ticks)
H4_UD_WRAPPER(pcl_h4_ud_assign_profile,   g_h4_ud_assign_orig,   g_h4_ud_assign_calls,   g_h4_ud_assign_ticks)
#undef H4_UD_WRAPPER

static i64 h4_update_direct_restore(u64 base) {
    const u8 create[18]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x81,0xEC,0xC0,0x00,0x00,0x00};
    const u8 aa[19]={0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x41,0x54,0x41,0x56,0x48,0x83,0xEC,0x30};
    const u8 ab[20]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xEC,0x30};
    const u8 pay[13]={0x48,0x89,0x5C,0x24,0x10,0x57,0x48,0x83,0xEC,0x40,0x48,0x8B,0xFA};
    const u8 disp[16]={0x48,0x8B,0xC4,0x55,0x48,0x8B,0xEC,0x48,0x83,0xEC,0x70,0x48,0x89,0x70,0x18,0x48};
    // disp length 16 above would split the next instruction; use 15 bytes through opcode payload? corrected below via explicit 19-byte signature.
    const u8 disp19[19]={0x48,0x8B,0xC4,0x55,0x48,0x8B,0xEC,0x48,0x83,0xEC,0x70,0x48,0x89,0x70,0x18,0x48,0x89,0x78,0xF0};
    (void)disp;
    const u8 post[14]={0x40,0x53,0x48,0x83,0xEC,0x20,0x33,0xC0,0x48,0x8B,0xD9,0x48,0x89,0x01};
    const u8 alloc[13]={0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,0xEC,0x20,0x48,0x8B,0xDA};
    const u8 assign[12]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0x12,0x48,0x8B,0xD9};
    bool ok=true;
    ok &= h4_nested_restore_one(base+0x01499270ull,assign,12,g_h4_ud_assign_saved,(u64)&pcl_h4_ud_assign_profile);
    ok &= h4_nested_restore_one(base+0x010F6C80ull,alloc,13,g_h4_ud_alloc_saved,(u64)&pcl_h4_ud_alloc_profile);
    ok &= h4_nested_restore_one(base+0x01237540ull,post,14,g_h4_ud_post_saved,(u64)&pcl_h4_ud_post_profile);
    ok &= h4_nested_restore_one(base+0x03B9F8E0ull,disp19,19,g_h4_ud_dispatch_saved,(u64)&pcl_h4_ud_dispatch_profile);
    ok &= h4_nested_restore_one(base+0x04007B90ull,pay,13,g_h4_ud_payload_saved,(u64)&pcl_h4_ud_payload_profile);
    ok &= h4_nested_restore_one(base+0x010D1A90ull,ab,20,g_h4_ud_array_b_saved,(u64)&pcl_h4_ud_array_b_profile);
    ok &= h4_nested_restore_one(base+0x010D0F20ull,aa,19,g_h4_ud_array_a_saved,(u64)&pcl_h4_ud_array_a_profile);
    ok &= h4_nested_restore_one(base+0x0400A680ull,create,18,g_h4_ud_create_saved,(u64)&pcl_h4_ud_create_profile);
    g_h4_update_direct_stock_restored=ok?1:0;
    if(ok){g_h4_update_direct_active=0;return 1;}
    return -428;
}

static i64 h4_update_direct_install(u64 base) {
    if(g_h4_update_direct_active) return -401;
    if(!h4_resolve_patch_api()) return -402;
    const u8 create[18]={0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x81,0xEC,0xC0,0x00,0x00,0x00};
    const u8 aa[19]={0x48,0x89,0x6C,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x41,0x54,0x41,0x56,0x48,0x83,0xEC,0x30};
    const u8 ab[20]={0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xEC,0x30};
    const u8 pay[13]={0x48,0x89,0x5C,0x24,0x10,0x57,0x48,0x83,0xEC,0x40,0x48,0x8B,0xFA};
    const u8 disp[19]={0x48,0x8B,0xC4,0x55,0x48,0x8B,0xEC,0x48,0x83,0xEC,0x70,0x48,0x89,0x70,0x18,0x48,0x89,0x78,0xF0};
    const u8 post[14]={0x40,0x53,0x48,0x83,0xEC,0x20,0x33,0xC0,0x48,0x8B,0xD9,0x48,0x89,0x01};
    const u8 alloc[13]={0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,0xEC,0x20,0x48,0x8B,0xDA};
    const u8 assign[12]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0x12,0x48,0x8B,0xD9};
    if(!h4_nested_patch_one(base+0x0400A680ull,create,18,g_h4_ud_create_saved,g_h4_ud_create_tramp,(u64)&pcl_h4_ud_create_profile)) return -403;
    g_h4_ud_create_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_create_tramp;
    if(!h4_nested_patch_one(base+0x010D0F20ull,aa,19,g_h4_ud_array_a_saved,g_h4_ud_array_a_tramp,(u64)&pcl_h4_ud_array_a_profile)){h4_update_direct_restore(base);return -404;} g_h4_ud_array_a_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_array_a_tramp;
    if(!h4_nested_patch_one(base+0x010D1A90ull,ab,20,g_h4_ud_array_b_saved,g_h4_ud_array_b_tramp,(u64)&pcl_h4_ud_array_b_profile)){h4_update_direct_restore(base);return -405;} g_h4_ud_array_b_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_array_b_tramp;
    if(!h4_nested_patch_one(base+0x04007B90ull,pay,13,g_h4_ud_payload_saved,g_h4_ud_payload_tramp,(u64)&pcl_h4_ud_payload_profile)){h4_update_direct_restore(base);return -406;} g_h4_ud_payload_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_payload_tramp;
    if(!h4_nested_patch_one(base+0x03B9F8E0ull,disp,19,g_h4_ud_dispatch_saved,g_h4_ud_dispatch_tramp,(u64)&pcl_h4_ud_dispatch_profile)){h4_update_direct_restore(base);return -407;} g_h4_ud_dispatch_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_dispatch_tramp;
    if(!h4_nested_patch_one(base+0x01237540ull,post,14,g_h4_ud_post_saved,g_h4_ud_post_tramp,(u64)&pcl_h4_ud_post_profile)){h4_update_direct_restore(base);return -408;} g_h4_ud_post_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_post_tramp;
    if(!h4_nested_patch_one(base+0x010F6C80ull,alloc,13,g_h4_ud_alloc_saved,g_h4_ud_alloc_tramp,(u64)&pcl_h4_ud_alloc_profile)){h4_update_direct_restore(base);return -409;} g_h4_ud_alloc_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_alloc_tramp;
    if(!h4_nested_patch_one(base+0x01499270ull,assign,12,g_h4_ud_assign_saved,g_h4_ud_assign_tramp,(u64)&pcl_h4_ud_assign_profile)){h4_update_direct_restore(base);return -410;} g_h4_ud_assign_orig=(H4UpdateAny6Fn)(void*)g_h4_ud_assign_tramp;
    g_h4_update_direct_active=1; g_h4_update_direct_stock_restored=0; return 1;
}

static i64 h4_scope_install(u64 base) {
    if (g_h4_scope_active) return -81;
    if (!h4_resolve_patch_api()) return -82;

    const u64 target = base + 0x045F8080ull;
    const u8 stock_sig[15] = {
        0x48,0x8B,0xC4,0x48,0x89,0x58,0x10,0x48,
        0x89,0x70,0x18,0x48,0x89,0x78,0x20
    };
    if (!h4_bytes_match(target, stock_sig, 15)) return -83;

    ULONG old_tramp = 0, old_target = 0;
    if (!h4_protect_rwx(g_h4_scope_tramp, 64, &old_tramp)) return -84;
    if (!h4_protect_rwx((void*)target, 15, &old_target)) {
        h4_restore_protection(g_h4_scope_tramp, 64, old_tramp);
        return -85;
    }

    for (u32 i = 0; i < 15; ++i) {
        const u8 b = rd<u8>(target + i);
        g_h4_scope_saved[i] = b;
        g_h4_scope_tramp[i] = b;
    }
    h4_emit_abs_jump(g_h4_scope_tramp + 15, target + 15);
    for (u32 i = 29; i < 64; ++i) g_h4_scope_tramp[i] = 0xCC;
    h4_flush_code(g_h4_scope_tramp, 64);

    u8 patch[15];
    for (u32 i = 0; i < 15; ++i) patch[i] = 0x90;
    h4_emit_abs_jump(patch, (u64)&pcl_h4_scope_passthrough);
    for (u32 i = 0; i < 15; ++i) wr<u8>(target + i, patch[i]);
    h4_flush_code((void*)target, 15);
    h4_restore_protection((void*)target, 15, old_target);

    (void)old_tramp; // trampoline intentionally remains executable while DLL is loaded
    g_h4_scope_orig = (H4Fn)(void*)g_h4_scope_tramp;
    g_h4_scope_owner_teb = get_teb();
    g_h4_scope_active = 1;
    g_h4_scope_stock_restored = 0;
    return 1;
}

static i64 h4_scope_restore(u64 base) {
    const u64 target = base + 0x045F8080ull;
    const u8 stock_sig[15] = {
        0x48,0x8B,0xC4,0x48,0x89,0x58,0x10,0x48,
        0x89,0x70,0x18,0x48,0x89,0x78,0x20
    };

    if (!g_h4_scope_active) {
        g_h4_scope_stock_restored = h4_bytes_match(target, stock_sig, 15) ? 1 : 0;
        return g_h4_scope_stock_restored ? 0 : -91;
    }

    const u8 detour_prefix[6] = {0xFF,0x25,0x00,0x00,0x00,0x00};
    if (!h4_bytes_match(target, detour_prefix, 6) ||
        rd<u64>(target + 6) != (u64)&pcl_h4_scope_passthrough) {
        g_h4_scope_stock_restored = 0;
        return -92;
    }

    ULONG old_target = 0;
    if (!h4_protect_rwx((void*)target, 15, &old_target)) {
        g_h4_scope_stock_restored = 0;
        return -93;
    }
    for (u32 i = 0; i < 15; ++i) wr<u8>(target + i, g_h4_scope_saved[i]);
    h4_flush_code((void*)target, 15);
    h4_restore_protection((void*)target, 15, old_target);

    g_h4_scope_stock_restored = h4_bytes_match(target, stock_sig, 15) ? 1 : 0;
    if (g_h4_scope_stock_restored) {
        g_h4_scope_active = 0;
        g_h4_scope_owner_teb = 0;
        g_h4_scope_orig = 0;
        return 1;
    }
    return -94;
}

// Lua 5.4 x64 layout, verified against liblua5.4 in the build environment:
// lua_State.ci at +0x20; CallInfo.func at +0x00; TValue size 16;
// integer TValue tag at +0x08 is LUA_VNUMINT (3).
static bool lua_arg_integer(void* state, int arg_index, u64* out) {
    if (!state || !out || arg_index < 1) return false;
    const u64 L = (u64)state;
    const u64 ci = rd<u64>(L + 0x20);
    if (!ci) return false;
    const u64 func = rd<u64>(ci + 0x00);
    if (!func) return false;
    const u64 tv = func + ((u64)arg_index * 16ull);
    const u8 tt = rd<u8>(tv + 0x08);
    if ((tt & 0x0Fu) != 3u) return false; // LUA_TNUMBER
    *out = rd<u64>(tv + 0x00);
    return true;
}

static int lua_return_integer(void* state, i64 value) {
    if (!state) return 0;
    const u64 L = (u64)state;
    const u64 top = rd<u64>(L + 0x10);
    if (!top) return 0;
    *(volatile i64*)(top + 0x00) = value;
    *(volatile u8*)(top + 0x08) = 3u; // LUA_VNUMINT
    *(volatile u64*)(L + 0x10) = top + 16ull;
    return 1;
}

static u32 h4_geometry_state_for_source(u64 source) {
    if (!source) return 0;
    u32 idx = h4_source_hash(source);
    for (u32 n = 0; n < H4_SOURCE_CAP; ++n) {
        H4SourceEntry* e = &g_h4_sources[(idx + n) & (H4_SOURCE_CAP - 1u)];
        if (e->source == source) return e->geometry_state;
        if (e->source == 0) return 0;
    }
    return 0;
}

static u32 h4_cache_state_for_source(u64 source) {
    if (!source) return 0;
    u32 idx = h4_source_hash(source);
    for (u32 n = 0; n < H4_SOURCE_CAP; ++n) {
        H4SourceEntry* e = &g_h4_sources[(idx + n) & (H4_SOURCE_CAP - 1u)];
        if (e->source == source) return e->cache_state;
        if (e->source == 0) return 0;
    }
    return 0;
}

static void h4_geometry_state_counts(i64* stable, i64* unstable, i64* unresolved) {
    i64 s = 0, u = 0, r = 0;
    for (u32 i = 0; i < H4_SOURCE_CAP; ++i) {
        H4SourceEntry* e = &g_h4_sources[i];
        if (!e->source) continue;
        if (e->geometry_state == 2u) ++s;
        else if (e->geometry_state == 3u) ++u;
        else ++r;
    }
    if (stable) *stable = s;
    if (unstable) *unstable = u;
    if (unresolved) *unresolved = r;
}

extern "C" __declspec(dllexport) int pcl_native_h4_scope_stats(void* lua_state) {
    int n = 0;
    n += lua_return_integer(lua_state, g_h4_scope_install_status);      // 1
    n += lua_return_integer(lua_state, g_h4_scope_restore_status);      // 2
    n += lua_return_integer(lua_state, g_h4_scope_calls);               // 3
    n += lua_return_integer(lua_state, g_h4_scope_active);              // 4
    n += lua_return_integer(lua_state, g_h4_scope_stock_restored);      // 5
    n += lua_return_integer(lua_state, g_h4_unique_sources);            // 6
    n += lua_return_integer(lua_state, g_h4_repeat_calls);              // 7
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_first_ticks)); // 8
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_repeat_ticks));// 9
    n += lua_return_integer(lua_state, (i64)g_h4_max_calls_per_source); // 10
    n += lua_return_integer(lua_state, (i64)g_h4_max_source_ptr);       // 11
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_max_source_ticks)); // 12
    n += lua_return_integer(lua_state, g_h4_null_source_calls);         // 13
    n += lua_return_integer(lua_state, g_h4_table_overflow);            // 14
    n += lua_return_integer(lua_state, (i64)g_h4_hot_source_ptr);       // 15
    n += lua_return_integer(lua_state, (i64)g_h4_hot_source_calls);     // 16
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_hot_source_ticks)); // 17
    n += lua_return_integer(lua_state, (i64)H4_SOURCE_CAP);             // 18
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_total_ticks)); // 19
    n += lua_return_integer(lua_state, g_h4_qpf > 0 ? 1 : 0);           // 20
    n += lua_return_integer(lua_state, g_h4_profile_calls);             // 21
    n += lua_return_integer(lua_state, g_h4_other_thread_calls);        // 22
    n += lua_return_integer(lua_state, g_h4_fp_sources_captured);       // 23
    n += lua_return_integer(lua_state, g_h4_fp_sources_validated);      // 24
    n += lua_return_integer(lua_state, g_h4_fp_sources_mismatch);       // 25
    n += lua_return_integer(lua_state, g_h4_fp_guard_fail);             // 26
    n += lua_return_integer(lua_state, g_h4_fp_checks);                 // 27
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_fp_hash_ticks)); // 28
    n += lua_return_integer(lua_state, g_h4_fp_index_bytes);            // 29
    n += lua_return_integer(lua_state, g_h4_fp_vertex_bytes);           // 30
    n += lua_return_integer(lua_state, (i64)g_h4_fp_first_mismatch_source); // 31
    n += lua_return_integer(lua_state, (i64)g_h4_fp_first_mismatch_code); // 32
    n += lua_return_integer(lua_state, g_h4_fp_geometry_validated);       // 33
    n += lua_return_integer(lua_state, g_h4_fp_geometry_mismatch);        // 34
    n += lua_return_integer(lua_state, g_h4_fp_bounds_only_mismatch);     // 35
    n += lua_return_integer(lua_state, g_h4_fp_bounds_mismatch);          // 36
    n += lua_return_integer(lua_state, g_h4_fp_index_num_mismatch);       // 37
    n += lua_return_integer(lua_state, g_h4_fp_vertex_num_mismatch);      // 38
    n += lua_return_integer(lua_state, g_h4_fp_index_hash_mismatch);      // 39
    n += lua_return_integer(lua_state, g_h4_fp_vertex_hash_mismatch);     // 40
    n += lua_return_integer(lua_state, (i64)g_h4_fp_first_geometry_mismatch_source); // 41
    n += lua_return_integer(lua_state, (i64)g_h4_fp_first_geometry_mismatch_code);   // 42
    i64 stable_sources = 0, unstable_sources = 0, unresolved_sources = 0;
    h4_geometry_state_counts(&stable_sources, &unstable_sources, &unresolved_sources);
    n += lua_return_integer(lua_state, stable_sources);                              // 43
    n += lua_return_integer(lua_state, unstable_sources);                            // 44
    n += lua_return_integer(lua_state, unresolved_sources);                          // 45
    n += lua_return_integer(lua_state, g_h4_stable_post_calls);                      // 46
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_stable_post_ticks));        // 47
    n += lua_return_integer(lua_state, g_h4_unstable_post_calls);                    // 48
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_unstable_post_ticks));      // 49
    n += lua_return_integer(lua_state, g_h4_unresolved_repeat_calls);                 // 50
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_unresolved_repeat_ticks));  // 51
    n += lua_return_integer(lua_state, (i64)h4_geometry_state_for_source(g_h4_hot_source_ptr)); // 52
    n += lua_return_integer(lua_state, (i64)h4_geometry_state_for_source(g_h4_max_source_ptr)); // 53
    n += lua_return_integer(lua_state, g_h4_loop_install_status);                               // 54
    n += lua_return_integer(lua_state, g_h4_loop_restore_status);                               // 55
    n += lua_return_integer(lua_state, g_h4_loop_active);                                       // 56
    n += lua_return_integer(lua_state, g_h4_loop_stock_restored);                               // 57
    n += lua_return_integer(lua_state, g_h4_cache_promoted_sources);                            // 58
    n += lua_return_integer(lua_state, g_h4_cache_rejected_sources);                            // 59
    n += lua_return_integer(lua_state, g_h4_cache_late_demotions);                              // 60
    n += lua_return_integer(lua_state, g_h4_cache_fast_calls);                                  // 61
    n += lua_return_integer(lua_state, g_h4_cache_fast_bytes);                                  // 62
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_cache_copy_ticks));                    // 63
    n += lua_return_integer(lua_state, g_h4_cache_mid_guard_fail);                              // 64
    n += lua_return_integer(lua_state, g_h4_cache_canary_calls);                                // 65
    n += lua_return_integer(lua_state, g_h4_cache_canary_mismatch);                             // 66
    n += lua_return_integer(lua_state, g_h4_cache_proof_checks);                                // 67
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_cache_proof_ticks));                   // 68
    n += lua_return_integer(lua_state, (i64)g_h4_vertex_cache_used);                            // 69
    n += lua_return_integer(lua_state, (i64)H4_VERTEX_CACHE_CAP);                               // 70
    n += lua_return_integer(lua_state, g_h4_cache_arena_rejects);                               // 71
    n += lua_return_integer(lua_state, (i64)h4_cache_state_for_source(g_h4_hot_source_ptr));    // 72
    n += lua_return_integer(lua_state, (i64)h4_cache_state_for_source(g_h4_max_source_ptr));    // 73
    n += lua_return_integer(lua_state, g_h4_post_install_status);                                // 74
    n += lua_return_integer(lua_state, g_h4_post_restore_status);                                // 75
    n += lua_return_integer(lua_state, g_h4_post_active);                                        // 76
    n += lua_return_integer(lua_state, g_h4_post_stock_restored);                                // 77
    n += lua_return_integer(lua_state, g_h4_post_vertex_copy_calls);                             // 78
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_post_vertex_copy_ticks));               // 79
    n += lua_return_integer(lua_state, g_h4_post_index_copy_calls);                              // 80
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_post_index_copy_ticks));                // 81
    n += lua_return_integer(lua_state, g_h4_post_component_build_calls);                         // 82
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_post_component_build_ticks));           // 83
    n += lua_return_integer(lua_state, g_h4_post_component_final_calls);                         // 84
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_post_component_final_ticks));           // 85
    const i64 post_sum_ticks = g_h4_post_vertex_copy_ticks + g_h4_post_index_copy_ticks +
                               g_h4_post_component_build_ticks + g_h4_post_component_final_ticks;
    n += lua_return_integer(lua_state, h4_qpc_to_us(post_sum_ticks));                            // 86
    n += lua_return_integer(lua_state, g_h4_nested_install_status);                              // 87
    n += lua_return_integer(lua_state, g_h4_nested_restore_status);                              // 88
    n += lua_return_integer(lua_state, g_h4_nested_active);                                      // 89
    n += lua_return_integer(lua_state, g_h4_nested_stock_restored);                              // 90
    n += lua_return_integer(lua_state, g_h4_nested_grow_calls);                                  // 91
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_nested_grow_ticks));                    // 92
    n += lua_return_integer(lua_state, g_h4_nested_payload_a_calls);                             // 93
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_nested_payload_a_ticks));               // 94
    n += lua_return_integer(lua_state, g_h4_nested_payload_b_calls);                             // 95
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_nested_payload_b_ticks));               // 96
    n += lua_return_integer(lua_state, g_h4_nested_recalc_calls);                                // 97
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_nested_recalc_ticks));                  // 98
    n += lua_return_integer(lua_state, g_h4_nested_update_calls);                                // 99
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_nested_update_ticks));                  // 100
    n += lua_return_integer(lua_state, g_h4_nested_tail_calls);                                  // 101
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_nested_tail_ticks));                    // 102
    n += lua_return_integer(lua_state, g_h4_update_direct_install_status);                        // 103
    n += lua_return_integer(lua_state, g_h4_update_direct_restore_status);                        // 104
    n += lua_return_integer(lua_state, g_h4_update_direct_active);                                // 105
    n += lua_return_integer(lua_state, g_h4_update_direct_stock_restored);                        // 106
    n += lua_return_integer(lua_state, g_h4_ud_create_calls);                                     // 107
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_create_ticks));                       // 108
    n += lua_return_integer(lua_state, g_h4_ud_array_a_calls);                                    // 109
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_array_a_ticks));                      // 110
    n += lua_return_integer(lua_state, g_h4_ud_array_b_calls);                                    // 111
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_array_b_ticks));                      // 112
    n += lua_return_integer(lua_state, g_h4_ud_payload_calls);                                    // 113
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_payload_ticks));                      // 114
    n += lua_return_integer(lua_state, g_h4_ud_dispatch_calls);                                   // 115
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_dispatch_ticks));                     // 116
    n += lua_return_integer(lua_state, g_h4_ud_post_calls);                                       // 117
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_post_ticks));                         // 118
    n += lua_return_integer(lua_state, g_h4_ud_alloc_calls);                                      // 119
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_alloc_ticks));                        // 120
    n += lua_return_integer(lua_state, g_h4_ud_assign_calls);                                     // 121
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ud_assign_ticks));                       // 122
    n += lua_return_integer(lua_state, g_h4_update_card_before_items);                             // 123
    n += lua_return_integer(lua_state, g_h4_update_card_after_items);                              // 124
    n += lua_return_integer(lua_state, g_h4_update_card_nonzero_calls);                            // 125
    n += lua_return_integer(lua_state, g_h4_update_card_zero_calls);                               // 126
    n += lua_return_integer(lua_state, g_h4_update_card_max_before);                               // 127
    n += lua_return_integer(lua_state, g_h4_update_card_guard_fail);                               // 128
    n += lua_return_integer(lua_state, g_h4_ut_tail_calls);                                       // 129
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ut_tail_ticks));                          // 130
    n += lua_return_integer(lua_state, g_h4_ut_pre_calls);                                        // 131
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ut_pre_ticks));                           // 132
    n += lua_return_integer(lua_state, g_h4_ut_dirty_calls);                                      // 133
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ut_dirty_ticks));                         // 134
    n += lua_return_integer(lua_state, g_h4_ut_dispatch_calls);                                   // 135
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_ut_dispatch_ticks));                      // 136
    n += lua_return_integer(lua_state, g_h4_vt_patched);                                          // 137
    n += lua_return_integer(lua_state, g_h4_vt_peak);                                             // 138
    n += lua_return_integer(lua_state, g_h4_vt_patch_fail);                                       // 139
    n += lua_return_integer(lua_state, g_h4_vt_restore_fail);                                     // 140
    n += lua_return_integer(lua_state, g_h4_vt_guard_fail);                                       // 141
    n += lua_return_integer(lua_state, g_h4_v2d0_calls);                                          // 142
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2d0_ticks));                            // 143
    n += lua_return_integer(lua_state, g_h4_v2b0_calls);                                          // 144
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_ticks));                            // 145
    n += lua_return_integer(lua_state, (i64)g_h4_vt_first);                                      // 146
    n += lua_return_integer(lua_state, (i64)g_h4_vt_first_rva);                                  // 147
    n += lua_return_integer(lua_state, (i64)g_h4_v2d0_target);                                   // 148
    n += lua_return_integer(lua_state, (i64)g_h4_v2d0_target_rva);                               // 149
    n += lua_return_integer(lua_state, (i64)g_h4_v2b0_target);                                   // 150
    n += lua_return_integer(lua_state, (i64)g_h4_v2b0_target_rva);                               // 151
    n += lua_return_integer(lua_state, g_h4_v2b0_target_in_image);                               // 152
    n += lua_return_integer(lua_state, (i64)g_h4_v2b0_sig0);                                    // 153
    n += lua_return_integer(lua_state, (i64)g_h4_v2b0_sig1);                                    // 154
    n += lua_return_integer(lua_state, (i64)g_h4_v2b0_sig2);                                    // 155
    n += lua_return_integer(lua_state, (i64)g_h4_v2b0_sig3);                                    // 156
    n += lua_return_integer(lua_state, g_h4_vt_capture_count);                                   // 157
    n += lua_return_integer(lua_state, g_h4_v2b0_target_mismatch);                               // 158
    n += lua_return_integer(lua_state, g_h4_v2b0_heavy_calls);                                    // 159
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_heavy_ticks));                      // 160
    n += lua_return_integer(lua_state, g_h4_v2b0_early_calls);                                    // 161
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_early_ticks));                      // 162
    n += lua_return_integer(lua_state, g_h4_v2b0_heavy_entries);                                  // 163
    n += lua_return_integer(lua_state, g_h4_v2b0_heavy_entry_max);                                // 164
    n += lua_return_integer(lua_state, g_h4_v2b0_zero_inner_entries);                             // 165
    n += lua_return_integer(lua_state, g_h4_v2b0_subcount_total);                                 // 166
    n += lua_return_integer(lua_state, g_h4_v2b0_subcount_max);                                   // 167
    n += lua_return_integer(lua_state, g_h4_v2b0_ptr310_nonzero);                                 // 168
    n += lua_return_integer(lua_state, g_h4_v2b0_structure_guard_fail);                           // 169
    n += lua_return_integer(lua_state, g_h4_v2b0_child_install_status);                              // 170
    n += lua_return_integer(lua_state, g_h4_v2b0_child_restore_status);                              // 171
    n += lua_return_integer(lua_state, g_h4_v2b0_child_active);                                      // 172
    n += lua_return_integer(lua_state, g_h4_v2b0_child_stock_restored);                              // 173
    n += lua_return_integer(lua_state, g_h4_v2b0_r3ba29a0_calls);                                   // 174
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3ba29a0_ticks));                      // 175
    n += lua_return_integer(lua_state, g_h4_v2b0_r3b87e20_calls);                                   // 176
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3b87e20_ticks));                      // 177
    n += lua_return_integer(lua_state, g_h4_v2b0_r3b8ade0_calls);                                   // 178
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3b8ade0_ticks));                      // 179
    n += lua_return_integer(lua_state, g_h4_v2b0_r3b895c0_calls);                                   // 180
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3b895c0_ticks));                      // 181
    n += lua_return_integer(lua_state, g_h4_v2b0_r3b9bab0_calls);                                   // 182
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3b9bab0_ticks));                      // 183
    n += lua_return_integer(lua_state, g_h4_v2b0_r3ba2790_calls);                                   // 184
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3ba2790_ticks));                      // 185
    n += lua_return_integer(lua_state, g_h4_v2b0_r3b8b430_calls);                                   // 186
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3b8b430_ticks));                      // 187
    n += lua_return_integer(lua_state, g_h4_v2b0_r13ef490_calls);                                   // 188
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r13ef490_ticks));                      // 189
    n += lua_return_integer(lua_state, g_h4_v2b0_r3b9a3d0_calls);                                   // 190
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_v2b0_r3b9a3d0_ticks));                      // 191
    const i64 v2b0_child_sum_ticks = g_h4_v2b0_r3ba29a0_ticks + g_h4_v2b0_r3b87e20_ticks +
        g_h4_v2b0_r3b8ade0_ticks + g_h4_v2b0_r3b895c0_ticks + g_h4_v2b0_r3b9bab0_ticks +
        g_h4_v2b0_r3ba2790_ticks + g_h4_v2b0_r3b8b430_ticks + g_h4_v2b0_r13ef490_ticks +
        g_h4_v2b0_r3b9a3d0_ticks;
    n += lua_return_integer(lua_state, h4_qpc_to_us(v2b0_child_sum_ticks));                           // 192
    n += lua_return_integer(lua_state, g_h4_v2b0_child_guard_fail);                                  // 193
    n += lua_return_integer(lua_state, g_h4_bab0_child_install_status);                              // 194
    n += lua_return_integer(lua_state, g_h4_bab0_child_restore_status);                              // 195
    n += lua_return_integer(lua_state, g_h4_bab0_child_active);                                      // 196
    n += lua_return_integer(lua_state, g_h4_bab0_child_stock_restored);                              // 197
    n += lua_return_integer(lua_state, g_h4_bab0_r3b8c990_calls);                                   // 198
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_bab0_r3b8c990_ticks));                      // 199
    n += lua_return_integer(lua_state, g_h4_bab0_r3b98d20_calls);                                   // 200
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_bab0_r3b98d20_ticks));                      // 201
    n += lua_return_integer(lua_state, g_h4_bab0_r3ba15b0_calls);                                   // 202
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_bab0_r3ba15b0_ticks));                      // 203
    n += lua_return_integer(lua_state, g_h4_bab0_r10d1a90_calls);                                   // 204
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_bab0_r10d1a90_ticks));                      // 205
    const i64 bab0_child_sum_ticks = g_h4_bab0_r3b8c990_ticks + g_h4_bab0_r3b98d20_ticks +
        g_h4_bab0_r3ba15b0_ticks + g_h4_bab0_r10d1a90_ticks;
    n += lua_return_integer(lua_state, h4_qpc_to_us(bab0_child_sum_ticks));                           // 206
    n += lua_return_integer(lua_state, g_h4_bab0_child_guard_fail);                                  // 207
    n += lua_return_integer(lua_state, g_h4_d20_child_install_status);                               // 208
    n += lua_return_integer(lua_state, g_h4_d20_child_restore_status);                               // 209
    n += lua_return_integer(lua_state, g_h4_d20_child_active);                                       // 210
    n += lua_return_integer(lua_state, g_h4_d20_child_stock_restored);                               // 211
    n += lua_return_integer(lua_state, g_h4_d20_r10d0f20_calls);                                    // 212
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_d20_r10d0f20_ticks));                       // 213
    n += lua_return_integer(lua_state, g_h4_d20_r3b99a20_calls);                                    // 214
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_d20_r3b99a20_ticks));                       // 215
    n += lua_return_integer(lua_state, g_h4_d20_r1a297f0_calls);                                    // 216
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_d20_r1a297f0_ticks));                       // 217
    n += lua_return_integer(lua_state, g_h4_d20_r3b7acf0_calls);                                    // 218
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_d20_r3b7acf0_ticks));                       // 219
    n += lua_return_integer(lua_state, g_h4_d20_r3b7b3a0_calls);                                    // 220
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_d20_r3b7b3a0_ticks));                       // 221
    const i64 d20_child_sum_ticks = g_h4_d20_r10d0f20_ticks + g_h4_d20_r3b99a20_ticks +
        g_h4_d20_r1a297f0_ticks + g_h4_d20_r3b7acf0_ticks + g_h4_d20_r3b7b3a0_ticks;
    n += lua_return_integer(lua_state, h4_qpc_to_us(d20_child_sum_ticks));                            // 222
    n += lua_return_integer(lua_state, g_h4_d20_child_guard_fail);                                   // 223
    n += lua_return_integer(lua_state, g_h4_a20_checks);                                             // 224
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_a20_hash_ticks));                            // 225
    n += lua_return_integer(lua_state, g_h4_a20_guard_fail);                                         // 226
    n += lua_return_integer(lua_state, g_h4_a20_promoted_sources);                                   // 227
    n += lua_return_integer(lua_state, g_h4_a20_rejected_sources);                                   // 228
    n += lua_return_integer(lua_state, g_h4_a20_late_demotions);                                     // 229
    n += lua_return_integer(lua_state, g_h4_a20_canary_calls);                                       // 230
    n += lua_return_integer(lua_state, g_h4_a20_canary_mismatch);                                    // 231
    n += lua_return_integer(lua_state, g_h4_a20_candidate_calls);                                    // 232
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_a20_candidate_ticks));                       // 233
    n += lua_return_integer(lua_state, g_h4_a20_proving_calls);                                      // 234
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_a20_proving_ticks));                         // 235
    n += lua_return_integer(lua_state, g_h4_a20_blocked_calls);                                      // 236
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_a20_blocked_ticks));                         // 237
    n += lua_return_integer(lua_state, g_h4_a20_output0_bytes);                                      // 238
    n += lua_return_integer(lua_state, g_h4_a20_output1_bytes);                                      // 239
    n += lua_return_integer(lua_state, (i64)g_h4_a20_first_mismatch_source);                          // 240
    n += lua_return_integer(lua_state, (i64)g_h4_a20_first_mismatch_code);                            // 241
    i64 a20_ready_sources=0, a20_rejected_current=0, a20_proving_sources=0, a20_max_matches=0;
    for (u32 i=0;i<H4_SOURCE_CAP;++i) {
        const H4SourceEntry* e=&g_h4_sources[i]; if(!e->source) continue;
        if(e->a20_state==2u) ++a20_ready_sources;
        else if(e->a20_state==3u) ++a20_rejected_current;
        else if(e->a20_state==1u) ++a20_proving_sources;
        if((i64)e->a20_matches>a20_max_matches) a20_max_matches=(i64)e->a20_matches;
    }
    n += lua_return_integer(lua_state, a20_ready_sources);                                            // 242
    n += lua_return_integer(lua_state, a20_rejected_current);                                        // 243
    n += lua_return_integer(lua_state, a20_proving_sources);                                         // 244
    n += lua_return_integer(lua_state, a20_max_matches);                                             // 245
    n += lua_return_integer(lua_state, g_h4_a20_output2_bytes);                                      // 246
    n += lua_return_integer(lua_state, g_h4_a20_output3_bytes);                                      // 247
    n += lua_return_integer(lua_state, g_h4_a20_cache_promoted_sources);                              // 248
    n += lua_return_integer(lua_state, g_h4_a20_cache_fast_calls);                                    // 249
    n += lua_return_integer(lua_state, g_h4_a20_cache_fast_bytes);                                    // 250
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_a20_cache_copy_ticks));                       // 251
    n += lua_return_integer(lua_state, (i64)g_h4_a20_cache_used);                                     // 252
    n += lua_return_integer(lua_state, (i64)H4_A20_CACHE_CAP);                                        // 253
    n += lua_return_integer(lua_state, g_h4_a20_cache_arena_rejects);                                 // 254
    n += lua_return_integer(lua_state, g_h4_a20_cache_fallback_calls);                                // 255
    n += lua_return_integer(lua_state, g_h4_a20_cache_apply_fail);                                    // 256
    n += lua_return_integer(lua_state, g_h4_a20_cache_resize_calls);                                  // 257
    n += lua_return_integer(lua_state, g_h4_a20_cache_resize_guard_ok);                               // 258
    n += lua_return_integer(lua_state, g_h4_f490_install_status);                                      // 259
    n += lua_return_integer(lua_state, g_h4_f490_restore_status);                                      // 260
    n += lua_return_integer(lua_state, g_h4_f490_active);                                              // 261
    n += lua_return_integer(lua_state, g_h4_f490_stock_restored);                                      // 262
    n += lua_return_integer(lua_state, g_h4_f490_calls);                                               // 263
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_ticks));                                 // 264
    n += lua_return_integer(lua_state, g_h4_f490_checks);                                              // 265
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_hash_ticks));                            // 266
    n += lua_return_integer(lua_state, g_h4_f490_guard_fail);                                          // 267
    n += lua_return_integer(lua_state, g_h4_f490_promoted_sources);                                    // 268
    n += lua_return_integer(lua_state, g_h4_f490_rejected_sources);                                    // 269
    n += lua_return_integer(lua_state, g_h4_f490_late_demotions);                                      // 270
    n += lua_return_integer(lua_state, g_h4_f490_canary_calls);                                        // 271
    n += lua_return_integer(lua_state, g_h4_f490_canary_mismatch);                                     // 272
    i64 f490_ready=0, f490_rejected_current=0, f490_proving=0, f490_max_matches=0;
    for (u32 i=0;i<H4_SOURCE_CAP;++i) {
        const H4SourceEntry* e=&g_h4_sources[i]; if(!e->source) continue;
        if(e->f490_state==2u) ++f490_ready;
        else if(e->f490_state==3u) ++f490_rejected_current;
        else if(e->f490_state==1u) ++f490_proving;
        if((i64)e->f490_matches>f490_max_matches) f490_max_matches=(i64)e->f490_matches;
    }
    n += lua_return_integer(lua_state, f490_ready);                                                     // 273
    n += lua_return_integer(lua_state, f490_rejected_current);                                         // 274
    n += lua_return_integer(lua_state, f490_proving);                                                  // 275
    n += lua_return_integer(lua_state, f490_max_matches);                                              // 276
    n += lua_return_integer(lua_state, g_h4_f490_candidate_calls);                                     // 277
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_candidate_ticks));                       // 278
    n += lua_return_integer(lua_state, g_h4_f490_proving_calls);                                       // 279
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_proving_ticks));                         // 280
    n += lua_return_integer(lua_state, g_h4_f490_blocked_calls);                                       // 281
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_blocked_ticks));                         // 282
    n += lua_return_integer(lua_state, (i64)g_h4_f490_first_mismatch_source);                          // 283
    n += lua_return_integer(lua_state, (i64)g_h4_f490_first_mismatch_code);                            // 284
    n += lua_return_integer(lua_state, g_h4_f490_mid_install_status);                                  // 285
    n += lua_return_integer(lua_state, g_h4_f490_mid_restore_status);                                  // 286
    n += lua_return_integer(lua_state, g_h4_f490_mid_active);                                          // 287
    n += lua_return_integer(lua_state, g_h4_f490_mid_stock_restored);                                  // 288
    n += lua_return_integer(lua_state, g_h4_f490_fast_calls);                                          // 289
    n += lua_return_integer(lua_state, g_h4_f490_fast_bytes);                                          // 290
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_fast_copy_ticks));                       // 291
    n += lua_return_integer(lua_state, g_h4_f490_fast_misses);                                         // 292
    n += lua_return_integer(lua_state, g_h4_f490_mid_guard_fail);                                      // 293
    n += lua_return_integer(lua_state, g_h4_f490_finalizer_install_status);                             // 294
    n += lua_return_integer(lua_state, g_h4_f490_finalizer_restore_status);                             // 295
    n += lua_return_integer(lua_state, g_h4_f490_finalizer_active);                                     // 296
    n += lua_return_integer(lua_state, g_h4_f490_finalizer_stock_restored);                             // 297
    n += lua_return_integer(lua_state, g_h4_f490_finalizer_calls);                                      // 298
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_finalizer_ticks));                        // 299
    n += lua_return_integer(lua_state, g_h4_f490_finalizer_guard_fail);                                 // 300
    n += lua_return_integer(lua_state, g_h4_f490_tail_install_status);                                 // 301
    n += lua_return_integer(lua_state, g_h4_f490_tail_restore_status);                                 // 302
    n += lua_return_integer(lua_state, g_h4_f490_tail_active);                                         // 303
    n += lua_return_integer(lua_state, g_h4_f490_tail_stock_restored);                                 // 304
    n += lua_return_integer(lua_state, g_h4_f490_tail_build_calls);                                    // 305
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_tail_build_ticks));                       // 306
    n += lua_return_integer(lua_state, g_h4_f490_tail_cleanup_calls);                                  // 307
    n += lua_return_integer(lua_state, h4_qpc_to_us(g_h4_f490_tail_cleanup_ticks));                     // 308
    n += lua_return_integer(lua_state, g_h4_f490_tail_guard_fail);                                     // 309
    return n;
}

static bool seam_signature_matches(u64 p) {
    // Accept the untouched stock seam.
    const u8 stock_sig[16] = {
        0x48,0x8B,0xC4,0x48,0x89,0x58,0x10,0x48,
        0x89,0x70,0x18,0x48,0x89,0x78,0x20,0x55
    };
    bool stock = true;
    for (int i=0;i<16;i++) {
        if (rd<u8>(p + (u64)i) != stock_sig[i]) { stock = false; break; }
    }
    if (stock) return true;

    // The 15.11.27 profiler replaces the 15-byte seam prologue with:
    //   FF 25 00 00 00 00 ; dq pcl_mw_seam_hook ; 90
    // Accept it only when both that complete patch shape and the exact current
    // profiler seam-hook prologue match. This does not accept an arbitrary detour.
    const u8 detour_prefix[6] = {0xFF,0x25,0x00,0x00,0x00,0x00};
    for (int i=0;i<6;i++) if (rd<u8>(p + (u64)i) != detour_prefix[i]) return false;
    if (rd<u8>(p + 14) != 0x90) return false;

    const u64 hook = rd<u64>(p + 6);
    if (hook < 0x10000ull) return false;
    // Accept only profiler hook prologues we have built and verified for this
    // exact game executable. Later profiler revisions change only the hook body;
    // the game-side detour shape remains the same and arbitrary detours are rejected.
    const u8 hook_sig_1527[16] = {
        0x56,0x57,0x48,0x83,0xEC,0x28,0x48,0x83,
        0x3D,0x42,0x3F,0x00,0x00,0x00,0x74,0x35
    };
    const u8 hook_sig_1540[16] = {
        0x56,0x57,0x48,0x83,0xEC,0x28,0x48,0x83,
        0x3D,0x42,0x5F,0x00,0x00,0x00,0x74,0x35
    };
    const u8 hook_sig_1543[16] = {
        0x41,0x56,0x56,0x57,0x55,0x53,0x48,0x83,
        0xEC,0x30,0x48,0x89,0xD7,0x48,0x89,0xCE
    };
    // 15.11.45 keeps the general-load hook but gates borrowed-array ownership
    // to explicit PCL-direct seams. Its optimized seam-hook prologue is:
    //   push r14; push rsi; push rdi; push rbx; sub rsp,28h;
    //   mov rsi,rdx; mov rdi,rcx; ...
    const u8 hook_sig_1545[16] = {
        0x41,0x56,0x56,0x57,0x53,0x48,0x83,0xEC,
        0x28,0x48,0x89,0xD6,0x48,0x89,0xCF,0x48
    };
    // 15.11.49 adds actor_make helper probes. That revision keeps the same
    // game-side 15-byte seam detour but its seam-hook saves rbp as well and
    // therefore has a distinct exact prologue. This is the first 16 bytes of
    // pcl_mw_seam_hook from the packaged 15.11.49 profiler object/DLL:
    //   push r14; push rsi; push rdi; push rbp; push rbx; sub rsp,30h;
    //   mov rsi,rdx; mov rdi,rcx
    const u8 hook_sig_1549[16] = {
        0x41,0x56,0x56,0x57,0x55,0x53,0x48,0x83,
        0xEC,0x30,0x48,0x89,0xD6,0x48,0x89,0xCF
    };
    bool prof_1527 = true, prof_1540 = true, prof_1543 = true,
         prof_1545 = true, prof_1549 = true;
    for (int i=0;i<16;i++) {
        const u8 b = rd<u8>(hook + (u64)i);
        if (b != hook_sig_1527[i]) prof_1527 = false;
        if (b != hook_sig_1540[i]) prof_1540 = false;
        if (b != hook_sig_1543[i]) prof_1543 = false;
        if (b != hook_sig_1545[i]) prof_1545 = false;
        if (b != hook_sig_1549[i]) prof_1549 = false;
    }
    return prof_1527 || prof_1540 || prof_1543 || prof_1545 || prof_1549;
}

extern "C" __declspec(dllexport) int pcl_native_rebuild(void* lua_state) {
    u64 forge = 0, piece = 0;
    if (!lua_arg_integer(lua_state, 1, &forge) ||
        !lua_arg_integer(lua_state, 2, &piece)) {
        return lua_return_integer(lua_state, -1);
    }

    const u64 base = get_main_module_base();
    if (!base) return lua_return_integer(lua_state, -2);

    // Guard against calling hard-coded RVAs on a different executable.
    if (rd<u16>(base + 0x00) != 0x5A4D) return lua_return_integer(lua_state, -3); // MZ
    const u32 peoff = rd<u32>(base + 0x3C);
    if (rd<u32>(base + peoff) != 0x00004550u) return lua_return_integer(lua_state, -3); // PE\0\0
    const u64 size_of_image_off = base + peoff + 0x18 + 0x38;
    if (rd<u32>(size_of_image_off) != 0x090A0000u) return lua_return_integer(lua_state, -3);

    const u64 seam_addr = base + 0x045AF640ull;
    if (!seam_signature_matches(seam_addr)) return lua_return_integer(lua_state, -4);

    if (forge < 0x10000ull || piece < 0x10000ull) return lua_return_integer(lua_state, -5);
    if (rd<u64>(forge + 0x3D8) != piece) return lua_return_integer(lua_state, -6);

    typedef void (PCL_MS_ABI *SeamFn)(void*, void*);
    SeamFn seam = (SeamFn)seam_addr;

    // 15.11.80: a previous seam must never leave a vtable slot patched. If a
    // prior fail-closed restoration did not complete, repair it before resetting
    // telemetry or touching any game code again.
    if (g_h4_vt_count != 0 && !h4_vtable_restore_all()) return lua_return_integer(lua_state, -7);

    // 15.11.73: both the H4 entry profiler and the vertex-loop bypass are scoped
    // to this synchronous native seam only. Either patch may fail open; the fast
    // path is enabled only when the mid-loop patch is active and a source passes
    // the eight-stock-output proof.
    h4_profile_reset();
    g_h4_loop_install_status = h4_loop_install(base);
    g_h4_loop_restore_status = 0;
    g_h4_post_install_status = h4_post_install(base);
    g_h4_post_restore_status = 0;
    g_h4_nested_install_status = h4_nested_install(base);
    g_h4_nested_restore_status = 0;
    g_h4_v2b0_child_install_status = h4_v2b0_child_install(base);
    g_h4_v2b0_child_restore_status = 0;
    g_h4_bab0_child_install_status = (g_h4_v2b0_child_install_status == 1) ? h4_bab0_child_install(base) : -549;
    g_h4_bab0_child_restore_status = 0;
    g_h4_d20_child_install_status = (g_h4_bab0_child_install_status == 1) ? h4_d20_child_install(base) : -569;
    g_h4_d20_child_restore_status = 0;
    g_h4_f490_install_status = (g_h4_d20_child_install_status == 1) ? h4_f490_install(base) : -603;
    g_h4_f490_restore_status = 0;
    g_h4_f490_mid_install_status = (g_h4_f490_install_status == 1) ? h4_f490_mid_install(base) : -625;
    g_h4_f490_mid_restore_status = 0;
    g_h4_f490_finalizer_install_status = (g_h4_f490_mid_install_status == 1) ? h4_f490_finalizer_install(base) : -645;
    g_h4_f490_finalizer_restore_status = 0;
    g_h4_f490_tail_install_status = (g_h4_f490_finalizer_install_status == 1) ? h4_f490_tail_install(base) : -665;
    g_h4_f490_tail_restore_status = 0;
    // 15.11.77: shared helper-entry detours are deliberately disabled; 15.11.76
    // proved that their million-call observer overhead materially distorted H4.
    g_h4_update_direct_install_status = 0;
    g_h4_update_direct_restore_status = 1;
    g_h4_update_direct_active = 0;
    g_h4_update_direct_stock_restored = 1;
    g_h4_scope_install_status = h4_scope_install(base);
    g_h4_scope_restore_status = 0;

    // If the entry wrapper failed to install, no cache decision can be made.
    // Remove the mid-loop hook before executing stock seam work.
    if (g_h4_scope_install_status != 1) {
        if (g_h4_f490_tail_active || g_h4_f490_tail_install_status != 1) g_h4_f490_tail_restore_status = h4_f490_tail_restore(base);
        if (g_h4_f490_finalizer_active || g_h4_f490_finalizer_install_status != 1) g_h4_f490_finalizer_restore_status = h4_f490_finalizer_restore(base);
        if (g_h4_f490_mid_active || g_h4_f490_mid_install_status != 1) g_h4_f490_mid_restore_status = h4_f490_mid_restore(base);
        if (g_h4_f490_active || g_h4_f490_install_status != 1) g_h4_f490_restore_status = h4_f490_restore(base);
        if (g_h4_d20_child_active || g_h4_d20_child_install_status != 1) g_h4_d20_child_restore_status = h4_d20_child_restore(base);
        if (g_h4_bab0_child_active || g_h4_bab0_child_install_status != 1) g_h4_bab0_child_restore_status = h4_bab0_child_restore(base);
        if (g_h4_v2b0_child_active || g_h4_v2b0_child_install_status != 1) g_h4_v2b0_child_restore_status = h4_v2b0_child_restore(base);
        if (g_h4_nested_active || g_h4_nested_install_status != 1) g_h4_nested_restore_status = h4_nested_restore(base);
        if (g_h4_post_active) g_h4_post_restore_status = h4_post_restore(base);
        if (g_h4_loop_active) g_h4_loop_restore_status = h4_loop_restore(base);
    }

    seam((void*)forge, (void*)piece);

    // Stop measurement/fast paths first, then remove the entry wrapper. Every game-side
    // patch is checked against its exact stock bytes before handoff.
    if (g_h4_f490_tail_active)
        g_h4_f490_tail_restore_status = h4_f490_tail_restore(base);
    else if (g_h4_f490_tail_restore_status == 0)
        g_h4_f490_tail_restore_status = h4_f490_tail_restore(base);
    if (g_h4_f490_finalizer_active)
        g_h4_f490_finalizer_restore_status = h4_f490_finalizer_restore(base);
    else if (g_h4_f490_finalizer_restore_status == 0)
        g_h4_f490_finalizer_restore_status = h4_f490_finalizer_restore(base);
    if (g_h4_f490_mid_active)
        g_h4_f490_mid_restore_status = h4_f490_mid_restore(base);
    else if (g_h4_f490_mid_restore_status == 0)
        g_h4_f490_mid_restore_status = h4_f490_mid_restore(base);
    if (g_h4_f490_active)
        g_h4_f490_restore_status = h4_f490_restore(base);
    else if (g_h4_f490_restore_status == 0)
        g_h4_f490_restore_status = h4_f490_restore(base);
    if (g_h4_d20_child_active)
        g_h4_d20_child_restore_status = h4_d20_child_restore(base);
    else if (g_h4_d20_child_restore_status == 0)
        g_h4_d20_child_restore_status = h4_d20_child_restore(base);
    if (g_h4_bab0_child_active)
        g_h4_bab0_child_restore_status = h4_bab0_child_restore(base);
    else if (g_h4_bab0_child_restore_status == 0)
        g_h4_bab0_child_restore_status = h4_bab0_child_restore(base);
    if (g_h4_v2b0_child_active)
        g_h4_v2b0_child_restore_status = h4_v2b0_child_restore(base);
    else if (g_h4_v2b0_child_restore_status == 0)
        g_h4_v2b0_child_restore_status = h4_v2b0_child_restore(base);
    if (g_h4_nested_active)
        g_h4_nested_restore_status = h4_nested_restore(base);
    else if (g_h4_nested_restore_status == 0)
        g_h4_nested_restore_status = h4_nested_restore(base);
    if (g_h4_post_active)
        g_h4_post_restore_status = h4_post_restore(base);
    else if (g_h4_post_restore_status == 0)
        g_h4_post_restore_status = h4_post_restore(base);
    if (g_h4_loop_active)
        g_h4_loop_restore_status = h4_loop_restore(base);
    else if (g_h4_loop_restore_status == 0)
        g_h4_loop_restore_status = h4_loop_restore(base);
    g_h4_scope_restore_status = h4_scope_restore(base);

    return lua_return_integer(lua_state, 1);
}


// 15.11.56: rearm only Bladesong's plain preview-state tail.
//
// The full pickup wrapper at 0x4627EA0 can take specialized selection branches
// which are correct for picking a part from a live construction but unsafe for a
// freshly reconstructed multi-part prefab. The stock plain-preview branch at
// 0x46280DF performs four state actions after assigning its preview pointer:
//   1) actor preview-state setup via 0x45F9AD0(actor, nullptr, true)
//   2) broadcast handling preview delegate at handling+0x178
//   3) update handling UI state from actor+0x324 via 0x45F90A0
//   4) broadcast the global preview-changed delegate at base+0x847CF90
// Lua performs the reflected PreviewSwordPartActor assignment first. This helper
// verifies that reflection maps to the exact stock pointer field at +0x128 before
// executing any state action, then runs only this non-selection tail.
extern "C" __declspec(dllexport) int pcl_native_rearm_preview(void* lua_state) {
    u64 handling = 0, actor = 0;
    if (!lua_arg_integer(lua_state, 1, &handling) ||
        !lua_arg_integer(lua_state, 2, &actor)) {
        return lua_return_integer(lua_state, -1);
    }

    const u64 base = get_main_module_base();
    if (!base) return lua_return_integer(lua_state, -2);
    if (rd<u16>(base + 0x00) != 0x5A4D) return lua_return_integer(lua_state, -3);
    const u32 peoff = rd<u32>(base + 0x3C);
    if (rd<u32>(base + peoff) != 0x00004550u) return lua_return_integer(lua_state, -3);
    if (rd<u32>(base + peoff + 0x18 + 0x38) != 0x090A0000u)
        return lua_return_integer(lua_state, -3);
    if (handling < 0x10000ull || actor < 0x10000ull)
        return lua_return_integer(lua_state, -5);

    const u64 actor_state_addr = base + 0x045F9AD0ull;
    const u64 delegate_addr    = base + 0x0111AF30ull;
    const u64 ui_state_addr    = base + 0x045F90A0ull;

    const u8 actor_state_sig[16] = {
        0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,
        0x24,0x10,0x48,0x89,0x7C,0x24,0x20,0x44
    };
    const u8 delegate_sig[16] = {
        0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x6C,
        0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57
    };
    const u8 ui_state_sig[16] = {
        0xF3,0x0F,0x5D,0x0D,0x24,0x92,0x14,0x02,
        0x48,0x8B,0x81,0xA0,0x03,0x00,0x00,0x0F
    };
    for (int i=0;i<16;i++) {
        if (rd<u8>(actor_state_addr + (u64)i) != actor_state_sig[i])
            return lua_return_integer(lua_state, -4);
        if (rd<u8>(delegate_addr + (u64)i) != delegate_sig[i])
            return lua_return_integer(lua_state, -4);
        if (rd<u8>(ui_state_addr + (u64)i) != ui_state_sig[i])
            return lua_return_integer(lua_state, -4);
    }

    // Critical guard: the reflected property write performed by Lua must map to
    // the exact pointer field used by the stock plain-preview branch.
    if (rd<u64>(handling + 0x128ull) != actor)
        return lua_return_integer(lua_state, -6);

    typedef void (PCL_MS_ABI *ActorStateFn)(void*, void*, unsigned char);
    typedef void (PCL_MS_ABI *DelegateFn)(void*, void*);
    typedef void (PCL_MS_ABI *UiStateFn)(void*, float);

    ActorStateFn actor_state = (ActorStateFn)actor_state_addr;
    DelegateFn broadcast = (DelegateFn)delegate_addr;
    UiStateFn ui_state = (UiStateFn)ui_state_addr;

    actor_state((void*)actor, (void*)0, (unsigned char)1);
    broadcast((void*)(handling + 0x178ull), (void*)actor);

    const u64 ui = rd<u64>(handling + 0xC8ull);
    if (ui >= 0x10000ull) {
        const float v = *(volatile float*)(actor + 0x324ull);
        ui_state((void*)ui, v);
    }

    broadcast((void*)(base + 0x0847CF90ull), (void*)actor);
    return lua_return_integer(lua_state, 1);
}


// ---------------------------------------------------------------------------
// Phase 15.11.63 - shipped Bladesong FWeaponDesignDefinition JSON serializer.
//
// Static reverse engineering of ForgeModeFrontend's built-in copy/paste path
// shows the game doing exactly this on COPY:
//   Piece = ForgeModeFrontend->Piece (+0x3B8)
//   Struct = FWeaponDesignDefinition::StaticStruct()          RVA 0x4580920
//   Json   = UStructToJsonObjectString(Struct, Piece+0x30, ...) RVA 0x20C5580
//   clipboard(Json)                                           RVA 0x1504B00
//
// This probe calls only those three read/export operations. It does not invoke
// the stock frontend copy/paste dispatcher, does not mutate Piece, and does not
// enter/rebuild ForgeMode. Lua passes the live Piece address plus the reflected
// AppliedSwordParts count; the bridge verifies Piece+0x30's raw design header
// agrees before calling any hard-coded RVA.
//
// Return value:
//   >0  UTF-16 FString Num generated by the game's serializer (includes NUL)
//   -1  bad Lua arguments
//   -2  no main module
//   -3  PE/image mismatch
//   -4  exact code signature mismatch
//   -5  bad Piece pointer / raw WeaponDesignDefinition sanity failure
//   -6  reflected expected AppliedSwordParts count != raw Piece design count
//   -7  serializer produced no FString data
//   -8  serializer output not JSON object/array text
extern "C" __declspec(dllexport) int pcl_native_copy_weapon_json(void* lua_state) {
    u64 piece = 0, expected_count_u = 0;
    if (!lua_arg_integer(lua_state, 1, &piece) ||
        !lua_arg_integer(lua_state, 2, &expected_count_u)) {
        return lua_return_integer(lua_state, -1);
    }

    const u64 base = get_main_module_base();
    if (!base) return lua_return_integer(lua_state, -2);
    if (rd<u16>(base + 0x00) != 0x5A4D) return lua_return_integer(lua_state, -3);
    const u32 peoff = rd<u32>(base + 0x3C);
    if (rd<u32>(base + peoff) != 0x00004550u) return lua_return_integer(lua_state, -3);
    if (rd<u32>(base + peoff + 0x18 + 0x38) != 0x090A0000u)
        return lua_return_integer(lua_state, -3);
    if (piece < 0x10000ull) return lua_return_integer(lua_state, -5);

    const u64 static_struct_addr = base + 0x04580920ull;
    const u64 serializer_addr    = base + 0x020C5580ull;
    const u64 clipboard_set_addr = base + 0x01504B00ull;
    const u64 free_addr          = base + 0x011531C0ull;

    const u8 static_struct_sig[16] = {
        0x48,0x83,0xEC,0x28,0x48,0x8B,0x05,0x7D,
        0xC2,0x27,0x04,0x48,0x85,0xC0,0x75,0x22
    };
    const u8 serializer_sig[16] = {
        0x48,0x89,0x5C,0x24,0x18,0x55,0x56,0x57,
        0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57
    };
    const u8 clipboard_sig[16] = {
        0x48,0x89,0x4C,0x24,0x08,0x48,0x83,0xEC,
        0x48,0xFF,0x15,0xE9,0x5A,0x20,0x05,0x48
    };
    const u8 free_sig[16] = {
        0x48,0x85,0xC9,0x74,0x2E,0x53,0x48,0x83,
        0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x0D
    };
    for (int i=0;i<16;i++) {
        if (rd<u8>(static_struct_addr + (u64)i) != static_struct_sig[i])
            return lua_return_integer(lua_state, -4);
        if (rd<u8>(serializer_addr + (u64)i) != serializer_sig[i])
            return lua_return_integer(lua_state, -4);
        if (rd<u8>(clipboard_set_addr + (u64)i) != clipboard_sig[i])
            return lua_return_integer(lua_state, -4);
        if (rd<u8>(free_addr + (u64)i) != free_sig[i])
            return lua_return_integer(lua_state, -4);
    }

    // Piece embeds FWeaponDesignDefinition at +0x30 in the shipped build.
    // Within that struct: RootSwordPartIdx +0x68, AppliedSwordParts +0x98,
    // Version +0xA8. TArray Num is Data+8, therefore raw count is Piece+0xD0.
    const i64 expected_count = (i64)expected_count_u;
    const i64 raw_count = (i64)(*(volatile int*)(piece + 0xD0ull));
    const i64 raw_max   = (i64)(*(volatile int*)(piece + 0xD4ull));
    const i64 root_idx  = (i64)(*(volatile int*)(piece + 0x98ull));
    const i64 version   = (i64)(*(volatile int*)(piece + 0xD8ull));
    const u64 arr_data  = rd<u64>(piece + 0xC8ull);

    if (raw_count < 0 || raw_count > 1000000 || raw_max < raw_count || raw_max > 1000000)
        return lua_return_integer(lua_state, -5);
    if (raw_count > 0 && arr_data < 0x10000ull)
        return lua_return_integer(lua_state, -5);
    if (raw_count > 0 && (root_idx < 0 || root_idx >= raw_count))
        return lua_return_integer(lua_state, -5);
    if (version < -1 || version > 64)
        return lua_return_integer(lua_state, -5);
    if (raw_count != expected_count)
        return lua_return_integer(lua_state, -6);

    struct FStringProbe {
        unsigned short* Data;
        int Num;
        int Max;
    };
    FStringProbe out;
    out.Data = (unsigned short*)0;
    out.Num = 0;
    out.Max = 0;

    typedef void* (PCL_MS_ABI *StaticStructFn)();
    typedef unsigned char (PCL_MS_ABI *SerializeFn)(
        void*, void*, FStringProbe*, u64, u64, u64, u64, u64);
    typedef void (PCL_MS_ABI *ClipboardSetFn)(const unsigned short*);
    typedef void (PCL_MS_ABI *FreeFn)(void*);

    StaticStructFn static_struct = (StaticStructFn)static_struct_addr;
    SerializeFn serialize = (SerializeFn)serializer_addr;
    ClipboardSetFn clipboard_set = (ClipboardSetFn)clipboard_set_addr;
    FreeFn free_mem = (FreeFn)free_addr;

    void* script_struct = static_struct();
    if ((u64)script_struct < 0x10000ull)
        return lua_return_integer(lua_state, -5);

    // Mirrors the exact argument pattern at ForgeModeFrontend copy path
    // 0x45E5A24..0x45E5A63: R9=0; stack args 0,0,0,1.
    (void)serialize(script_struct, (void*)(piece + 0x30ull), &out,
                    0ull, 0ull, 0ull, 0ull, 1ull);

    if (!out.Data || out.Num <= 1 || out.Max < out.Num) {
        if (out.Data) free_mem((void*)out.Data);
        return lua_return_integer(lua_state, -7);
    }

    const unsigned short first = out.Data[0];
    if (first != (unsigned short)'{' && first != (unsigned short)'[') {
        free_mem((void*)out.Data);
        return lua_return_integer(lua_state, -8);
    }

    clipboard_set(out.Data);
    const i64 result_num = (i64)out.Num;
    free_mem((void*)out.Data);
    return lua_return_integer(lua_state, result_num);
}

// ---------------------------------------------------------------------------
// Phase 15.11.64 - shipped Bladesong JSON -> temporary FWeaponDesignDefinition
// validation probe.
//
// This is deliberately READ-ONLY with respect to the live Piece. Lua places the
// exported JSON file on the Windows clipboard. The bridge then follows the same
// native sequence used by ForgeModeFrontend's built-in Paste action:
//
//   clipboard getter                                   RVA 0x1504BF0
//   initialize temporary FWeaponDesignDefinition      RVA 0x4631C10
//   JsonObjectStringToUStruct wrapper                  RVA 0x45CB7D0
//   FWeaponDesignDefinition migration/fixup            RVA 0x46382C0
//   destroy temporary FWeaponDesignDefinition          RVA 0x452FCE0
//
// No copy into Piece+0x30 is performed in this phase and no Forge rebuild is
// called. A positive return is the parsed AppliedSwordParts count.
//
// Return:
//   >0 parsed part count, with root/count/version/TArray/tree sanity verified
//   -20 module/PE guard
//   -21 exact signature guard failed
//   -22 clipboard empty/not JSON-shaped
//   -23 temporary WDD parse returned false
//   -24 WDD raw header sanity failed
//   -25 SlotChildren/FreeChildren header/index sanity failed
//   -26 parsed graph edge-count sanity failed
extern "C" __declspec(dllexport) int pcl_native_validate_weapon_json(void* lua_state) {
    const u64 base = get_main_module_base();
    if (!base) return lua_return_integer(lua_state, -20);
    if (rd<u16>(base + 0x00) != 0x5A4D) return lua_return_integer(lua_state, -20);
    const u32 peoff = rd<u32>(base + 0x3C);
    if (rd<u32>(base + peoff) != 0x00004550u) return lua_return_integer(lua_state, -20);
    if (rd<u32>(base + peoff + 0x18 + 0x38) != 0x090A0000u)
        return lua_return_integer(lua_state, -20);

    const u64 clipboard_get_addr = base + 0x01504BF0ull;
    const u64 wdd_init_addr      = base + 0x04631C10ull;
    const u64 json_parse_addr    = base + 0x045CB7D0ull;
    const u64 wdd_fixup_addr     = base + 0x046382C0ull;
    const u64 wdd_destroy_addr   = base + 0x0452FCE0ull;
    const u64 static_struct_addr = base + 0x04580920ull;
    const u64 free_addr          = base + 0x011531C0ull;

    const u8 clipboard_get_sig[16] = {
        0x48,0x89,0x4C,0x24,0x08,0x48,0x81,0xEC,
        0x98,0x00,0x00,0x00,0xFF,0x15,0xF6,0x59
    };
    const u8 wdd_init_sig[16] = {
        0x48,0x8B,0xC4,0x48,0x89,0x48,0x08,0x55,
        0x53,0x56,0x57,0x41,0x56,0x41,0x57,0x48
    };
    const u8 json_parse_sig[16] = {
        0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,
        0x24,0x10,0x48,0x89,0x7C,0x24,0x18,0x4C
    };
    const u8 wdd_fixup_sig[16] = {
        0x48,0x8B,0xC4,0x53,0x48,0x81,0xEC,0xB0,
        0x00,0x00,0x00,0x83,0xB9,0xA8,0x00,0x00
    };
    const u8 wdd_destroy_sig[16] = {
        0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,
        0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x89
    };
    const u8 static_struct_sig[16] = {
        0x48,0x83,0xEC,0x28,0x48,0x8B,0x05,0x7D,
        0xC2,0x27,0x04,0x48,0x85,0xC0,0x75,0x22
    };
    const u8 free_sig[16] = {
        0x48,0x85,0xC9,0x74,0x2E,0x53,0x48,0x83,
        0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x0D
    };

    const u64 sig_addrs[7] = {
        clipboard_get_addr, wdd_init_addr, json_parse_addr, wdd_fixup_addr,
        wdd_destroy_addr, static_struct_addr, free_addr
    };
    const u8* sigs[7] = {
        clipboard_get_sig, wdd_init_sig, json_parse_sig, wdd_fixup_sig,
        wdd_destroy_sig, static_struct_sig, free_sig
    };
    for (int s=0;s<7;s++) {
        for (int i=0;i<16;i++) {
            if (rd<u8>(sig_addrs[s] + (u64)i) != sigs[s][i])
                return lua_return_integer(lua_state, -21);
        }
    }

    struct FStringProbe64 {
        u16* Data;
        int Num;
        int Max;
    } clip;
    clip.Data = (u16*)0;
    clip.Num = 0;
    clip.Max = 0;

    typedef void (PCL_MS_ABI *ClipboardGetFn)(FStringProbe64*);
    typedef void (PCL_MS_ABI *WddInitFn)(void*);
    typedef unsigned char (PCL_MS_ABI *JsonParseFn)(
        const FStringProbe64*, void*, u64, u64, u64, u64, u64);
    typedef void (PCL_MS_ABI *WddFixupFn)(void*);
    typedef void (PCL_MS_ABI *WddDestroyFn)(void*);
    typedef void (PCL_MS_ABI *FreeFn)(void*);

    ClipboardGetFn clipboard_get = (ClipboardGetFn)clipboard_get_addr;
    WddInitFn wdd_init = (WddInitFn)wdd_init_addr;
    JsonParseFn json_parse = (JsonParseFn)json_parse_addr;
    WddFixupFn wdd_fixup = (WddFixupFn)wdd_fixup_addr;
    WddDestroyFn wdd_destroy = (WddDestroyFn)wdd_destroy_addr;
    FreeFn game_free = (FreeFn)free_addr;

    clipboard_get(&clip);
    if (!clip.Data || clip.Num <= 1 || clip.Max < clip.Num ||
        (clip.Data[0] != (u16)'{' && clip.Data[0] != (u16)'[')) {
        if (clip.Data) game_free((void*)clip.Data);
        return lua_return_integer(lua_state, -22);
    }

    alignas(16) u8 wdd[0x100];
    for (int i=0;i<0x100;i++) wdd[i] = 0;
    wdd_init((void*)wdd);

    const unsigned char parsed =
        json_parse(&clip, (void*)wdd, 0, 0, 0, 0, 0);
    if (!parsed) {
        wdd_destroy((void*)wdd);
        if (clip.Data) game_free((void*)clip.Data);
        return lua_return_integer(lua_state, -23);
    }

    wdd_fixup((void*)wdd);

    const int root_idx   = *(volatile int*)(wdd + 0x68);
    const u64 parts_data = *(volatile u64*)(wdd + 0x98);
    const int part_num   = *(volatile int*)(wdd + 0xA0);
    const int part_max   = *(volatile int*)(wdd + 0xA4);
    const int version    = *(volatile int*)(wdd + 0xA8);
    const int blade_num  = *(volatile int*)(wdd + 0x90);
    const int blade_max  = *(volatile int*)(wdd + 0x94);

    bool header_ok =
        part_num > 0 && part_num <= 1000000 &&
        part_max >= part_num && part_max <= 1000000 &&
        parts_data >= 0x10000ull &&
        root_idx >= 0 && root_idx < part_num &&
        version >= 0 && version <= 64 &&
        blade_num >= 0 && blade_num <= part_num &&
        blade_max >= blade_num && blade_max <= 1000000;

    i64 slot_edges = 0;
    i64 free_edges = 0;
    bool graph_ok = header_ok;

    if (header_ok) {
        for (int p=0; p<part_num && graph_ok; ++p) {
            const u64 part = parts_data + ((u64)p * 0x120ull);

            const u64 slot_data = rd<u64>(part + 0xD0ull);
            const int slot_num  = *(volatile int*)(part + 0xD8ull);
            const int slot_max  = *(volatile int*)(part + 0xDCull);
            if (slot_num < 0 || slot_num > 100000 ||
                slot_max < slot_num || slot_max > 100000 ||
                (slot_num > 0 && slot_data < 0x10000ull)) {
                graph_ok = false;
                break;
            }
            for (int s=0; s<slot_num; ++s) {
                const int idx = *(volatile int*)(slot_data + ((u64)s * 4ull));
                if (idx < -1 || idx >= part_num) {
                    graph_ok = false;
                    break;
                }
                if (idx >= 0) ++slot_edges;
            }

            const u64 free_data = rd<u64>(part + 0xE0ull);
            const int free_num  = *(volatile int*)(part + 0xE8ull);
            const int free_max  = *(volatile int*)(part + 0xECull);
            if (free_num < 0 || free_num > 100000 ||
                free_max < free_num || free_max > 100000 ||
                (free_num > 0 && free_data < 0x10000ull)) {
                graph_ok = false;
                break;
            }
            free_edges += (i64)free_num;
        }
    }

    // For a complete WeaponDesignDefinition every non-root AppliedSwordPart is
    // reached exactly once by either SlotChildren, FreeChildren or BladeSwordParts.
    const i64 total_edges = slot_edges + free_edges + (i64)blade_num;
    const bool edge_ok = graph_ok && total_edges == (i64)part_num - 1;

    wdd_destroy((void*)wdd);
    if (clip.Data) game_free((void*)clip.Data);

    if (!header_ok) return lua_return_integer(lua_state, -24);
    if (!graph_ok) return lua_return_integer(lua_state, -25);
    if (!edge_ok) return lua_return_integer(lua_state, -26);
    return lua_return_integer(lua_state, (i64)part_num);
}

// ---------------------------------------------------------------------------
// Phase 15.11.65 - shipped JSON -> live Piece.WeaponDesignDefinition assignment.
//
// Mirrors only the data half of ForgeModeFrontend's stock Paste branch:
//   clipboard getter                0x1504BF0
//   temp WDD init                   0x4631C10
//   JSON -> temp WDD                0x45CB7D0
//   WDD migration/fixup             0x46382C0
//   WDD deep copy/assign            0x4540B60  (destination Piece+0x30)
//   temp WDD destroy                0x452FCE0
//
// Deliberately does NOT call Piece post-assignment update 0x45F5200 or the
// stock delegate broadcast. PCL feeds the populated Piece directly to the
// already-proven hidden-temp-Forge reconstruction seam instead.
//
// Lua arg 1: live Piece UObject address.
// Return >0: assigned AppliedSwordParts count.
// Negative values are fail-closed guards/parse/graph/assignment failures.
extern "C" __declspec(dllexport) int pcl_native_load_weapon_json_into_piece(void* lua_state) {
    u64 piece = 0;
    if (!lua_arg_integer(lua_state, 1, &piece))
        return lua_return_integer(lua_state, -30);
    if (piece < 0x10000ull)
        return lua_return_integer(lua_state, -31);

    const u64 base = get_main_module_base();
    if (!base) return lua_return_integer(lua_state, -32);
    if (rd<u16>(base + 0x00) != 0x5A4D) return lua_return_integer(lua_state, -32);
    const u32 peoff = rd<u32>(base + 0x3C);
    if (rd<u32>(base + peoff) != 0x00004550u) return lua_return_integer(lua_state, -32);
    if (rd<u32>(base + peoff + 0x18 + 0x38) != 0x090A0000u)
        return lua_return_integer(lua_state, -32);

    const u64 clipboard_get_addr = base + 0x01504BF0ull;
    const u64 wdd_init_addr      = base + 0x04631C10ull;
    const u64 json_parse_addr    = base + 0x045CB7D0ull;
    const u64 wdd_fixup_addr     = base + 0x046382C0ull;
    const u64 wdd_assign_addr    = base + 0x04540B60ull;
    const u64 wdd_destroy_addr   = base + 0x0452FCE0ull;
    const u64 applied_destroy_addr = base + 0x0452F0C0ull;
    const u64 free_addr          = base + 0x011531C0ull;

    const u8 clipboard_get_sig[16] = {
        0x48,0x89,0x4C,0x24,0x08,0x48,0x81,0xEC,
        0x98,0x00,0x00,0x00,0xFF,0x15,0xF6,0x59
    };
    const u8 wdd_init_sig[16] = {
        0x48,0x8B,0xC4,0x48,0x89,0x48,0x08,0x55,
        0x53,0x56,0x57,0x41,0x56,0x41,0x57,0x48
    };
    const u8 json_parse_sig[16] = {
        0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74,
        0x24,0x10,0x48,0x89,0x7C,0x24,0x18,0x4C
    };
    const u8 wdd_fixup_sig[16] = {
        0x48,0x8B,0xC4,0x53,0x48,0x81,0xEC,0xB0,
        0x00,0x00,0x00,0x83,0xB9,0xA8,0x00,0x00
    };
    const u8 wdd_assign_sig[16] = {
        0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x6C,
        0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57
    };
    const u8 wdd_destroy_sig[16] = {
        0x48,0x89,0x5C,0x24,0x08,0x57,0x48,0x83,
        0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x89
    };
    const u8 applied_destroy_sig[16] = {
        0x85,0xD2,0x74,0x46,0x48,0x89,0x5C,0x24,
        0x08,0x57,0x48,0x83,0xEC,0x20,0x8B,0xFA
    };
    const u8 free_sig[16] = {
        0x48,0x85,0xC9,0x74,0x2E,0x53,0x48,0x83,
        0xEC,0x20,0x48,0x8B,0xD9,0x48,0x8B,0x0D
    };
    // Most targets must remain exact stock. The applied-part destructor is the
    // one deliberate exception: the persistent PCL zero-copy profiler already
    // detours its non-zero path at +0x4. Accept either exact stock bytes or the
    // exact PCL RIP-indirect detour shape while keeping the initial test/jz stock.
    const u64 sig_addrs[7] = {
        clipboard_get_addr, wdd_init_addr, json_parse_addr, wdd_fixup_addr,
        wdd_assign_addr, wdd_destroy_addr, free_addr
    };
    const u8* sigs[7] = {
        clipboard_get_sig, wdd_init_sig, json_parse_sig, wdd_fixup_sig,
        wdd_assign_sig, wdd_destroy_sig, free_sig
    };
    for (int s=0; s<7; ++s)
        for (int i=0; i<16; ++i)
            if (rd<u8>(sig_addrs[s] + (u64)i) != sigs[s][i])
                return lua_return_integer(lua_state, -33);

    bool applied_prefix_stock = true;
    for (int i=0; i<4; ++i)
        if (rd<u8>(applied_destroy_addr + (u64)i) != applied_destroy_sig[i])
            applied_prefix_stock = false;

    bool applied_body_stock = true;
    for (int i=4; i<16; ++i)
        if (rd<u8>(applied_destroy_addr + (u64)i) != applied_destroy_sig[i])
            applied_body_stock = false;

    const u64 applied_nonzero = applied_destroy_addr + 4ull;
    const bool applied_body_pcl_detour =
        rd<u8>(applied_nonzero + 0) == 0xFF &&
        rd<u8>(applied_nonzero + 1) == 0x25 &&
        rd<u8>(applied_nonzero + 2) == 0x00 &&
        rd<u8>(applied_nonzero + 3) == 0x00 &&
        rd<u8>(applied_nonzero + 4) == 0x00 &&
        rd<u8>(applied_nonzero + 5) == 0x00 &&
        rd<u64>(applied_nonzero + 6) >= 0x10000ull &&
        rd<u8>(applied_nonzero + 14) == 0x90 &&
        rd<u8>(applied_nonzero + 15) == 0x90 &&
        rd<u8>(applied_nonzero + 16) == 0x90 &&
        rd<u8>(applied_nonzero + 17) == 0x90 &&
        rd<u8>(applied_nonzero + 18) == 0x90;

    if (!applied_prefix_stock || (!applied_body_stock && !applied_body_pcl_detour))
        return lua_return_integer(lua_state, -33);

    struct FStringProbe65 { u16* Data; int Num; int Max; } clip;
    clip.Data = (u16*)0; clip.Num = 0; clip.Max = 0;

    typedef void (PCL_MS_ABI *ClipboardGetFn)(FStringProbe65*);
    typedef void (PCL_MS_ABI *WddInitFn)(void*);
    typedef unsigned char (PCL_MS_ABI *JsonParseFn)(
        const FStringProbe65*, void*, u64, u64, u64, u64, u64);
    typedef void (PCL_MS_ABI *WddFixupFn)(void*);
    typedef void (PCL_MS_ABI *WddAssignFn)(void*, const void*);
    typedef void (PCL_MS_ABI *WddDestroyFn)(void*);
    typedef void (PCL_MS_ABI *AppliedDestroyFn)(void*, int);
    typedef void (PCL_MS_ABI *FreeFn)(void*);

    ClipboardGetFn clipboard_get = (ClipboardGetFn)clipboard_get_addr;
    WddInitFn wdd_init = (WddInitFn)wdd_init_addr;
    JsonParseFn json_parse = (JsonParseFn)json_parse_addr;
    WddFixupFn wdd_fixup = (WddFixupFn)wdd_fixup_addr;
    WddAssignFn wdd_assign = (WddAssignFn)wdd_assign_addr;
    WddDestroyFn wdd_destroy = (WddDestroyFn)wdd_destroy_addr;
    AppliedDestroyFn applied_destroy = (AppliedDestroyFn)applied_destroy_addr;
    FreeFn game_free = (FreeFn)free_addr;

    clipboard_get(&clip);
    if (!clip.Data || clip.Num <= 1 || clip.Max < clip.Num ||
        (clip.Data[0] != (u16)'{' && clip.Data[0] != (u16)'[')) {
        if (clip.Data) game_free((void*)clip.Data);
        return lua_return_integer(lua_state, -34);
    }

    alignas(16) u8 wdd[0x100];
    for (int i=0; i<0x100; ++i) wdd[i] = 0;
    wdd_init((void*)wdd);

    const unsigned char parsed = json_parse(&clip, (void*)wdd, 0, 0, 0, 0, 0);
    if (!parsed) {
        wdd_destroy((void*)wdd);
        if (clip.Data) game_free((void*)clip.Data);
        return lua_return_integer(lua_state, -35);
    }
    wdd_fixup((void*)wdd);

    const int root_idx        = *(volatile int*)(wdd + 0x68);
    const u64 blade_data      = *(volatile u64*)(wdd + 0x88);
    const int original_blades = *(volatile int*)(wdd + 0x90);
    const int blade_max       = *(volatile int*)(wdd + 0x94);
    const u64 parts_data      = *(volatile u64*)(wdd + 0x98);
    const int original_parts  = *(volatile int*)(wdd + 0xA0);
    const int part_max        = *(volatile int*)(wdd + 0xA4);
    const int version         = *(volatile int*)(wdd + 0xA8);

    bool header_ok =
        original_parts > 0 && original_parts <= 1000000 &&
        part_max >= original_parts && part_max <= 1000000 &&
        parts_data >= 0x10000ull && root_idx >= 0 && root_idx < original_parts &&
        version >= 0 && version <= 64 &&
        original_blades >= 0 && original_blades < original_parts &&
        blade_max >= original_blades && blade_max <= 1000000 &&
        (original_blades == 0 || blade_data >= 0x10000ull);

    i64 slot_edges = 0, free_edges = 0;
    bool graph_ok = header_ok;
    if (header_ok) {
        for (int p=0; p<original_parts && graph_ok; ++p) {
            const u64 part = parts_data + ((u64)p * 0x120ull);

            const u64 slot_data = rd<u64>(part + 0xD0ull);
            const int slot_num = *(volatile int*)(part + 0xD8ull);
            const int slot_max = *(volatile int*)(part + 0xDCull);
            if (slot_num < 0 || slot_num > 100000 || slot_max < slot_num ||
                slot_max > 100000 || (slot_num > 0 && slot_data < 0x10000ull)) {
                graph_ok = false; break;
            }
            for (int si=0; si<slot_num; ++si) {
                const int idx = *(volatile int*)(slot_data + ((u64)si * 4ull));
                if (idx < -1 || idx >= original_parts) { graph_ok = false; break; }
                if (idx >= 0) ++slot_edges;
            }

            const u64 free_data = rd<u64>(part + 0xE0ull);
            const int free_num = *(volatile int*)(part + 0xE8ull);
            const int free_max = *(volatile int*)(part + 0xECull);
            if (free_num < 0 || free_num > 100000 || free_max < free_num ||
                free_max > 100000 || (free_num > 0 && free_data < 0x10000ull)) {
                graph_ok = false; break;
            }
            for (int fi=0; fi<free_num; ++fi) {
                const int idx = *(volatile int*)(free_data + ((u64)fi * 0x40ull));
                if (idx < 0 || idx >= original_parts) { graph_ok = false; break; }
                ++free_edges;
            }
        }
    }

    const bool edge_ok = graph_ok &&
        (slot_edges + free_edges + (i64)original_blades == (i64)original_parts - 1);
    if (!header_ok || !graph_ok || !edge_ok) {
        wdd_destroy((void*)wdd);
        if (clip.Data) game_free((void*)clip.Data);
        return lua_return_integer(lua_state, !header_ok ? -36 : (!graph_ok ? -37 : -38));
    }

    // Phase 15.11.83: preconstructions are construction-only. Strip blade
    // metadata and matching AppliedSwordParts before assigning into the live
    // Piece. Fail closed unless every blade is an unreferenced contiguous tail,
    // so no construction index remapping is required.
    int filtered_parts = original_parts;
    if (original_blades > 0) {
        const int keep = original_parts - original_blades;
        if (keep <= 0 || root_idx < 0 || root_idx >= keep) {
            wdd_destroy((void*)wdd);
            if (clip.Data) game_free((void*)clip.Data);
            return lua_return_integer(lua_state, -41);
        }

        // BladeSwordPart is 0x50 bytes in this build; idx is its first int.
        for (int bi=0; bi<original_blades; ++bi) {
            const int idx = *(volatile int*)(blade_data + ((u64)bi * 0x50ull));
            if (idx < keep || idx >= original_parts) {
                wdd_destroy((void*)wdd);
                if (clip.Data) game_free((void*)clip.Data);
                return lua_return_integer(lua_state, -41);
            }
            int hits = 0;
            for (int bj=0; bj<original_blades; ++bj) {
                const int other = *(volatile int*)(blade_data + ((u64)bj * 0x50ull));
                if (other == idx) ++hits;
            }
            if (hits != 1) {
                wdd_destroy((void*)wdd);
                if (clip.Data) game_free((void*)clip.Data);
                return lua_return_integer(lua_state, -41);
            }
        }
        for (int expected=keep; expected<original_parts; ++expected) {
            int hits = 0;
            for (int bi=0; bi<original_blades; ++bi) {
                const int idx = *(volatile int*)(blade_data + ((u64)bi * 0x50ull));
                if (idx == expected) ++hits;
            }
            if (hits != 1) {
                wdd_destroy((void*)wdd);
                if (clip.Data) game_free((void*)clip.Data);
                return lua_return_integer(lua_state, -41);
            }
        }

        for (int p=0; p<keep; ++p) {
            const u64 part = parts_data + ((u64)p * 0x120ull);
            const u64 slot_data = rd<u64>(part + 0xD0ull);
            const int slot_num = *(volatile int*)(part + 0xD8ull);
            for (int si=0; si<slot_num; ++si) {
                const int idx = *(volatile int*)(slot_data + ((u64)si * 4ull));
                if (idx >= keep) {
                    wdd_destroy((void*)wdd);
                    if (clip.Data) game_free((void*)clip.Data);
                    return lua_return_integer(lua_state, -42);
                }
            }
            const u64 free_data = rd<u64>(part + 0xE0ull);
            const int free_num = *(volatile int*)(part + 0xE8ull);
            for (int fi=0; fi<free_num; ++fi) {
                const int idx = *(volatile int*)(free_data + ((u64)fi * 0x40ull));
                if (idx >= keep) {
                    wdd_destroy((void*)wdd);
                    if (clip.Data) game_free((void*)clip.Data);
                    return lua_return_integer(lua_state, -42);
                }
            }
        }

        // FAppliedSwordPart owns SlotChildren/FreeChildren allocations.
        // Destroy only the removed tail's internal arrays, then shrink Num so
        // the normal temp-WDD destructor will not double-destroy them.
        applied_destroy((void*)(parts_data + ((u64)keep * 0x120ull)), original_blades);
        *(volatile int*)(wdd + 0xA0) = keep;

        // Preserve BladeSwordParts Data/Max for normal temp-WDD cleanup.
        *(volatile int*)(wdd + 0x90) = 0;
        filtered_parts = keep;
    }

    const u64 dst = piece + 0x30ull;
    const u64 old_parts_data = rd<u64>(dst + 0x98ull);
    const int old_num = *(volatile int*)(dst + 0xA0ull);
    const int old_max = *(volatile int*)(dst + 0xA4ull);
    if (old_num < 0 || old_num > 1000000 || old_max < old_num || old_max > 1000000 ||
        (old_num > 0 && old_parts_data < 0x10000ull)) {
        wdd_destroy((void*)wdd);
        if (clip.Data) game_free((void*)clip.Data);
        return lua_return_integer(lua_state, -39);
    }

    wdd_assign((void*)dst, (const void*)wdd);

    const int out_root = *(volatile int*)(dst + 0x68ull);
    const u64 out_data = rd<u64>(dst + 0x98ull);
    const int out_num = *(volatile int*)(dst + 0xA0ull);
    const int out_max = *(volatile int*)(dst + 0xA4ull);
    const int out_blades = *(volatile int*)(dst + 0x90ull);
    const int out_version = *(volatile int*)(dst + 0xA8ull);
    const bool assigned_ok =
        out_num == filtered_parts && out_max >= out_num && out_data >= 0x10000ull &&
        out_root == root_idx && out_blades == 0 && out_version == version;

    wdd_destroy((void*)wdd);
    if (clip.Data) game_free((void*)clip.Data);
    if (!assigned_ok) return lua_return_integer(lua_state, -40);
    return lua_return_integer(lua_state, (i64)filtered_parts);
}
