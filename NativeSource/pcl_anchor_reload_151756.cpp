// Exact build layout: UPiece::WeaponDesignDefinition=0x30,
// AppliedSwordParts=0x98; FAppliedSwordPart stride=0x120;
// SwordPart FName=0x0, transient SwordPartData handle=0xF8.
// Never touch saved topology, version, transforms, arrays or normal part rows.
#include "pcl_anchor_catalogue_patch_15170.cpp"

static int rebind_piece(u64 piece,u64 piece_class,u64 table,u64 table_class,u64 name) {
    if (!sane_ptr(piece)||!sane_ptr(piece_class)||!sane_ptr(table)||!sane_ptr(table_class)||!name||name>0x7FFFFFFFull) return -2;
    __try {
        if (rd<u64>(piece+0x10)!=piece_class || rd<u64>(table+0x10)!=table_class) return -3;
        ArrView parts=arr_at(piece,0xC8);
        if (parts.num<0 || parts.num>6000 || parts.max<parts.num || parts.max>100000) return -4;
        if (!parts.num) return 0;
        if (!sane_ptr(parts.data)) return -5;
        // Validate all target identities before any writes.
        int changed=0;
        for (int i=0;i<parts.num;++i) {
            const u64 part=parts.data+(u64)i*0x120;
            if (rd<u64>(part)==name && (rd<u64>(part+0xF8)!=table || rd<u64>(part+0x100)!=name)) ++changed;
        }
        for (int i=0;i<parts.num;++i) {
            const u64 part=parts.data+(u64)i*0x120;
            if (rd<u64>(part)==name) {
                wr<u64>(part+0xF8,table);
                wr<u64>(part+0x100,name);
            }
        }
        return changed;
    } __except(1) { return -9; }
}

extern "C" __declspec(dllexport) int pcl_anchor_rebind_piece(void* L) {
    u64 piece=0,pc=0,table=0,tc=0,name=0;
    if (!lua_arg_integer(L,1,&piece)||!lua_arg_integer(L,2,&pc)||!lua_arg_integer(L,3,&table)||!lua_arg_integer(L,4,&tc)||!lua_arg_integer(L,5,&name)) return lua_return_integer(L,-1);
    return lua_return_integer(L,rebind_piece(piece,pc,table,tc,name));
}
