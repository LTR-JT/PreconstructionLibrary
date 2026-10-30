// 15.17.41: runtime-selectable primary-chain behavior; stock socket geometry unchanged.
// Retain the existing guarded row helpers and Lua 5.4 adapter unchanged.
#include "pcl_anchor_catalogue_patch_15170.cpp"
extern "C" { int _fltused = 0; }

static int check_socket_row(u64 row, u64 cls, u64 name_index, u64 primary) {
    if (!sane_ptr(row) || !sane_ptr(cls) || name_index == 0 || name_index > 0x7FFFFFFFull || primary > 1) return -2;
    const ArrView slots = arr_at(row, 0x130);
    if (!sane_ptr(slots.data) || slots.num != 1 || slots.max < 1 || slots.max > 64) return -4;
    if (rd<u8>(row + 0x20) != 2 || rd<u8>(row + 0x21) != 2 || rd<u8>(row + 0xD9) != primary) return -5;
    if (rd<u64>(row + 0x78) != cls) return -6;
    // FName is {ComparisonIndex:uint32, Number:uint32}; Default has no suffix.
    if (rd<u64>(slots.data) != name_index) return -7;
    if (rd<double>(slots.data + 0x08) != 0.0 || rd<double>(slots.data + 0x10) != 0.0 ||
        rd<double>(slots.data + 0x18) != 0.0) return -8;
    if (rd<u8>(slots.data + 0x20) || rd<u8>(slots.data + 0x21)) return -9;
    return 1;
}

extern "C" __declspec(dllexport) int pcl_anchor_check_socket_row(void* L) {
    u64 row=0, cls=0, name_index=0, primary=0;
    if (!lua_arg_integer(L,1,&row) || !lua_arg_integer(L,2,&cls) || !lua_arg_integer(L,3,&name_index) || !lua_arg_integer(L,4,&primary))
        return lua_return_integer(L,-1);
    return lua_return_integer(L,check_socket_row(row,cls,name_index,primary));
}

extern "C" __declspec(dllexport) int pcl_anchor_set_socket_row(void* L) {
    u64 row=0, cls=0, name_index=0, primary=0;
    if (!lua_arg_integer(L,1,&row) || !lua_arg_integer(L,2,&cls) || !lua_arg_integer(L,3,&name_index) || !lua_arg_integer(L,4,&primary))
        return lua_return_integer(L,-1);
    if (!sane_ptr(row) || !sane_ptr(cls) || name_index == 0 || name_index > 0x7FFFFFFFull || primary > 1)
        return lua_return_integer(L,-2);
    const ArrView slots = arr_at(row,0x130);
    if (!sane_ptr(slots.data) || slots.num < 1 || slots.num > 2 ||
        slots.max < slots.num || slots.max > 64) return lua_return_integer(L,-4);
    if (rd<u8>(row+0x20)!=2 || rd<u8>(row+0x21)!=2) return lua_return_integer(L,-5);
    if (slots.num == 2) copy_bytes(slots.data,slots.data+0x30,0x30);
    wr<u64>(slots.data,name_index);
    wr<double>(slots.data+0x08,0.0);
    wr<double>(slots.data+0x10,0.0);
    wr<double>(slots.data+0x18,0.0);
    wr<u8>(slots.data+0x20,0);
    wr<u8>(slots.data+0x21,0);
    wr<u32>(row+0x138,1);
    wr<u8>(row+0xD9,(u8)primary);
    wr<u64>(row+0x78,cls);
    return lua_return_integer(L,check_socket_row(row,cls,name_index,primary));
}
