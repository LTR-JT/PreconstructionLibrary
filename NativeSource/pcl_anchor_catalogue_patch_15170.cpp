// PCL 15.16.3 - native catalogue anchor row patch + raw verifier.
//
// This helper does NOT add/remove UDataTable rows and does not call game RVAs.
// Lua resolves three existing SwordPartData rows and passes their raw row-data
// addresses:
//   arg1 = destination TRIPLANAR_GRIP (dev-only backing row)
//   arg2 = 574_Hollow behavior donor (reserved for validation/future use)
//   arg3 = 80_Misc_Cube visual/handling/socket donor
//
// The destination keeps its own TMap/TArray containers. We copy only non-
// container field representations from Cube, then copy two SwordPartSlot
// elements (Left/Right) into the destination's already-allocated two-slot
// array. Finally Status is made usable and Type is set to GuardQuillon.
//
// SwordPartData offsets are from the UE4SS JMAP for this Bladesong build:
//   Status 0x20, Type 0x21, RenderAsset 0x28, Blueprint 0x78,
//   bHasPrimarySlot 0xD9, ForcedSlotFlippedState 0xE0,
//   Slots TArray 0x130, SlotsHistory TArray 0x140,
//   SurfaceArea 0x150, HighPolyMesh 0x188, PropertyLayers 0x1B0.
// SwordPartSlot is 0x30 bytes.

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef long long i64;

template <typename T> static inline T rd(u64 p) { return *(volatile T*)(p); }
template <typename T> static inline void wr(u64 p, T v) { *(volatile T*)(p) = v; }

static void copy_bytes(u64 dst, u64 src, u32 n) {
    for (u32 i = 0; i < n; ++i) wr<u8>(dst + i, rd<u8>(src + i));
}

// Lua 5.4 x64 layout used by UE4SS in this project.
static bool lua_arg_integer(void* state, int arg_index, u64* out) {
    if (!state || !out || arg_index < 1) return false;
    const u64 L = (u64)state;
    const u64 ci = rd<u64>(L + 0x20);
    if (!ci) return false;
    const u64 func = rd<u64>(ci + 0x00);
    if (!func) return false;
    const u64 tv = func + ((u64)arg_index * 16ull);
    const u8 tt = rd<u8>(tv + 0x08);
    if ((tt & 0x0Fu) != 3u) return false;
    *out = rd<u64>(tv + 0x00);
    return true;
}

static int lua_return_integer(void* state, i64 value) {
    if (!state) return 0;
    const u64 L = (u64)state;
    const u64 top = rd<u64>(L + 0x10);
    if (!top) return 0;
    wr<i64>(top + 0x00, value);
    wr<u8>(top + 0x08, 3u);
    wr<u64>(L + 0x10, top + 16ull);
    return 1;
}

static bool sane_ptr(u64 p) {
    return p >= 0x10000ull && p < 0x0000800000000000ull;
}

struct ArrView {
    u64 data;
    int num;
    int max;
};

static ArrView arr_at(u64 base, u64 off) {
    ArrView a;
    a.data = rd<u64>(base + off + 0x0);
    a.num  = (int)rd<u32>(base + off + 0x8);
    a.max  = (int)rd<u32>(base + off + 0xC);
    return a;
}

extern "C" __declspec(dllexport) int pcl_anchor_patch_row(void* L) {
    u64 dst = 0, hollow = 0, cube = 0;
    if (!lua_arg_integer(L, 1, &dst) ||
        !lua_arg_integer(L, 2, &hollow) ||
        !lua_arg_integer(L, 3, &cube)) {
        return lua_return_integer(L, -1); // bad Lua args
    }

    if (!sane_ptr(dst) || !sane_ptr(hollow) || !sane_ptr(cube))
        return lua_return_integer(L, -2);
    if (dst == cube || dst == hollow || cube == hollow)
        return lua_return_integer(L, -3);

    // Validate the destination and Cube slot arrays before any mutation.
    const ArrView dslots = arr_at(dst, 0x130);
    const ArrView cslots = arr_at(cube, 0x130);
    if (!sane_ptr(dslots.data) || dslots.num < 2 || dslots.max < dslots.num || dslots.max > 64)
        return lua_return_integer(L, -10);
    if (!sane_ptr(cslots.data) || cslots.num < 3 || cslots.max < cslots.num || cslots.max > 64)
        return lua_return_integer(L, -11);

    // Hollow donor is passed deliberately so we can validate that its row at
    // least looks like the known GuardQuillon donor before we patch.
    // Status/Type bytes are expected to be 2/2 for 574_Hollow in the current
    // data. Refuse if this is no longer true rather than blindly mutating.
    if (rd<u8>(hollow + 0x20) != 2u || rd<u8>(hollow + 0x21) != 2u)
        return lua_return_integer(L, -12);

    // Copy Cube's complete early non-container metadata block:
    // RenderAsset, Book, placement flags, rotation/bending fields, Blueprint,
    // mesh UV/normal/AO settings, display flags. Stop before the first TMap.
    copy_bytes(dst + 0x28, cube + 0x28, 0xB8); // [0x28, 0xE0)

    // Copy Cube's later non-container physical/handling metadata and
    // HighPolyMesh wrapper. Stop before PropertyLayers TMap.
    copy_bytes(dst + 0x150, cube + 0x150, 0x60); // [0x150, 0x1B0)

    // Make the row a normal usable GuardQuillon catalogue part.
    wr<u8>(dst + 0x20, 2u); // Status
    wr<u8>(dst + 0x21, 2u); // Type = GuardQuillon

    // Explicit safety/behavior values matching our proven rows.
    wr<u8>(dst + 0x58, 0u); // bHandGrip
    wr<u8>(dst + 0x59, 0u); // bPreventPlacingOnSurfaces
    wr<u8>(dst + 0x5A, 0u); // bWrapAroundBlade
    wr<u8>(dst + 0xD8, 0u); // bDisplayUpright
    wr<u8>(dst + 0xD9, 1u); // bHasPrimarySlot

    // Destination has exactly two preallocated slots. Use Cube's real side
    // socket definitions so gizmos and placement line up with cube geometry:
    //   dst slot 0 <- Cube slot 1 (Left)  : upstream/primary
    //   dst slot 1 <- Cube slot 2 (Right) : prefab/carry child
    const u32 SLOT_SIZE = 0x30;
    copy_bytes(dslots.data + 0 * SLOT_SIZE, cslots.data + 1 * SLOT_SIZE, SLOT_SIZE);
    copy_bytes(dslots.data + 1 * SLOT_SIZE, cslots.data + 2 * SLOT_SIZE, SLOT_SIZE);

    // The new catalogue row is cloned from 574_Hollow and therefore starts
    // with three slots. The anchor intentionally exposes only two. The slot
    // element type is trivially stored data (FName/vector/bools/UV), so reducing
    // Num from 3 to 2 does not require destroying heap-owning members.
    wr<u32>(dst + 0x130 + 0x8, 2u);

    // Return a compact verification signature:
    // 1 means patch applied and key invariants still look sane.
    const ArrView verify = arr_at(dst, 0x130);
    if (rd<u8>(dst + 0x20) != 2u || rd<u8>(dst + 0x21) != 2u ||
        rd<u8>(dst + 0xD9) != 1u || verify.data != dslots.data || verify.num != 2) {
        return lua_return_integer(L, -20);
    }

    return lua_return_integer(L, 1);
}


extern "C" __declspec(dllexport) int pcl_anchor_inspect_row(void* L) {
    u64 row = 0;
    if (!lua_arg_integer(L, 1, &row))
        return lua_return_integer(L, -1);
    if (!sane_ptr(row))
        return lua_return_integer(L, -2);

    const ArrView slots = arr_at(row, 0x130);
    if (!sane_ptr(slots.data) || slots.num < 0 || slots.num > 255 ||
        slots.max < slots.num || slots.max > 255)
        return lua_return_integer(L, -3);

    const u8 status = rd<u8>(row + 0x20);
    const u8 type = rd<u8>(row + 0x21);
    const u8 primary = rd<u8>(row + 0xD9) ? 1u : 0u;
    const u32 packed =
        ((u32)status) |
        ((u32)type << 8) |
        ((u32)primary << 16) |
        (((u32)slots.num & 0xFFu) << 24);

    return lua_return_integer(L, (i64)packed);
}


// 15.17.0: safely replace SwordPartData.Blueprint (ClassProperty @ 0x78)
// with a loaded UClass pointer supplied by Lua. Unlike RenderAsset, Blueprint
// is a direct 8-byte class pointer in the reflected SwordPartData layout.
extern "C" __declspec(dllexport) int pcl_anchor_set_blueprint_class(void* L) {
    u64 row = 0, cls = 0;
    if (!lua_arg_integer(L, 1, &row) ||
        !lua_arg_integer(L, 2, &cls)) {
        return lua_return_integer(L, -1);
    }
    if (!sane_ptr(row) || !sane_ptr(cls))
        return lua_return_integer(L, -2);

    // Finalize after the legacy donor patch and reflected socket writes.
    // One outgoing connector; placement uses the actor origin rather than
    // reserving another visible socket as a primary/upstream connector.
    const ArrView slots = arr_at(row, 0x130);
    if (!sane_ptr(slots.data) || slots.num < 1 || slots.num > 2 ||
        slots.max < slots.num || slots.max > 64 ||
        rd<u8>(row + 0x20) != 2u || rd<u8>(row + 0x21) != 2u)
        return lua_return_integer(L, -4);
    if (slots.num == 2) copy_bytes(slots.data, slots.data + 0x30, 0x30);
    wr<u32>(row + 0x138, 1u);
    wr<u8>(row + 0xD9, 0u);
    wr<u64>(row + 0x78, cls);

    if (rd<u64>(row + 0x78) != cls)
        return lua_return_integer(L, -3);

    return lua_return_integer(L, 1);
}

extern "C" int __stdcall DllMain(void*, unsigned long, void*) { return 1; }
