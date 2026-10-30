// PCL 15.17.62: library downloads bypass Creative inventory registration.
// Only two CALL instructions in the verified callback are redirected. Unarmed and
// other-widget calls still invoke the original. The replacement does no spawn,
// rebuild, Lua callback, allocation, or actor traversal in the HTTP callback.
// A world-owned temporary Forge holds the downloaded UPiece through its UPROPERTY.
// Lua later constructs the tree on that isolated host and assigns the preview.
typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef long long i64;
extern "C" __declspec(dllimport) void* __stdcall GetModuleHandleW(const void*);
extern "C" __declspec(dllimport) void* __stdcall VirtualAlloc(void*,u64,u32,u32);
extern "C" __declspec(dllimport) int __stdcall VirtualProtect(void*,u64,u32,u32*);
extern "C" __declspec(dllimport) int __stdcall FlushInstructionCache(void*,const void*,u64);
extern "C" __declspec(dllimport) u32 __stdcall GetCurrentThreadId();
extern "C" __declspec(dllimport) u64 __stdcall GetTickCount64();
template<class T> static T rd(u64 p) { return *(volatile T*)p; }
template<class T> static void wr(u64 p,T v) { *(volatile T*)p=v; }
static bool ptr(u64 p) { return p>=0x10000 && p<0x800000000000ull; }
static bool same(u64 p,const u8* b,u32 n) {
    for(u32 i=0;i<n;++i) if(rd<u8>(p+i)!=b[i]) return false;
    return true;
}
static bool arg(void* L,int n,u64& v) {
    if(!L) return false;
    u64 ci=rd<u64>((u64)L+0x20); if(!ptr(ci)) return false;
    u64 f=rd<u64>(ci); if(!ptr(f)) return false;
    u64 tv=f+16ull*n;
    if(rd<u8>(tv+8)!=3) return false; // integer, not a float payload
    v=rd<u64>(tv); return true;
}
static int result(void* L,i64 v) {
    if(!L) return 0;
    u64 top=rd<u64>((u64)L+0x10); if(!ptr(top)) return 0;
    wr<i64>(top,v); wr<u8>(top+8,3); wr<u64>((u64)L+0x10,top+16); return 1;
}
static const u8 call_bytes[]={0xE8,0x96,0x20,0xF7,0xFF};
static const u8 callback_prologue[]={0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x56,0x41,0x57,0x48,0x8D,0xAC,0x24,0xE0,0xFE,0xFF,0xFF};
static const u8 seam_prologue[]={0x48,0x8B,0xC4,0x48,0x89,0x58,0x10,0x48,0x89,0x70,0x18,0x48,0x89,0x78,0x20,0x55};
static const u8 piece_store[]={0x4C,0x89,0xB6,0xD8,0x03,0x00,0x00};
static const u8 forge_store[]={0x48,0x89,0x9D,0x48,0x04,0x00,0x00};
static const u8 callback_widget[]={0x48,0x8B,0xF9,0x48,0x89,0x54,0x24,0x48};
static const u8 call_arguments[]={0x48,0x8B,0xD6,0x48,0x8B,0xCB};
static const u8 enter_prologue[]={0x48,0x89,0x5C,0x24,0x18,0x55,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57};
static const u8 weak_assign_prologue[]={0x40,0x53,0x48,0x83,0xEC,0x20,0x48,0x8B,0x12,0x48,0x8B,0xD9,0x48,0x85,0xD2,0x74,0x1A};
static const u8 weak_array_reference[]={0x48,0x8D,0x0D,0x63,0x91,0x1B,0x07,0xE8,0xFE,0x19,0xFE,0xFF};
static const u8 weak_serial_layout[]={0x8B,0x47,0x10,0x85,0xC0};
static const u8 object_array_layout[]={0x3B,0x51,0x24,0x7D,0x1C,0x4C,0x8B,0x41,0x10,0x44,0x8B,0xCA,0x0F,0xB7,0xC2,0x49,0xC1,0xE9,0x10,0x48,0x8D,0x14,0x40,0x4B,0x8B,0x04,0xC8,0x48,0x8D,0x3C,0xD0};
static const u8 factory_call[]={0xe8,0xb2,0xd8,0xf6,0xff};
static const u8 factory_arguments[]={0x45,0x33,0xc0,0x48,0x8d,0x54,0x24,0x60,0x48,0x8b,0xce};
static const u8 factory_prologue[]={0x48,0x89,0x5c,0x24,0x8,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xec,0x20};
static const u8 new_piece_prologue[]={0x40,0x53,0x48,0x81,0xec,0xb0,0x0,0x0,0x0,0x48,0x8b,0x5,0x80,0xfa,0xf7,0x3,0x48,0x33,0xc4,0x48};
static const u8 load_piece_prologue[]={0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x48,0x83,0xec,0x20,0x48,0x8b,0xd9,0x48};
static const u8 factory_add_inventory[]={0x48,0x8b,0x8c,0xf5,0x38,0x5,0x0,0x0,0x48,0x8b,0xd7,0xe8,0x6f,0x49,0xff,0xff};
struct Weak { u32 index,serial; };
struct Capture {
    u64 widget,gm,active,temp,before,piece_class,deadline;
    u32 thread;
    int status; // 0 idle, 1 waiting, 2 captured, negatives refuse/cancel
    bool home; // data-only capture into UWPieceInventoryEntry.BoundPiece
};
static Capture capture={};
static u64 image=0, relay=0;
static u8 patch[5]={}, factory_patch[5]={};
static bool installed=false;
static u64 object_array=0;
static Weak weak_objects[6]={};
typedef void (*Enter)(u64,u64);
static Enter original=0;
typedef u64 (*Factory)(u64,u64,u8);
typedef u64 (*NewPiece)(u64);
typedef void (*LoadPiece)(u64,u64);
static Factory original_factory=0;
static NewPiece create_piece=0;
static LoadPiece load_piece=0;
// Check saved index/serial in GUObjectArray before dereferencing a cached
// UObject. An address-range check alone cannot protect against GC or reuse.
static bool weak_valid(Weak h,u64 expected) {
    if(!ptr(object_array) || !h.serial || h.index>=rd<u32>(object_array+0x24)) return false;
    u64 chunks=rd<u64>(object_array+0x10); if(!ptr(chunks)) return false;
    u64 chunk=rd<u64>(chunks+8ull*(h.index>>16)); if(!ptr(chunk)) return false;
    u64 item=chunk+24ull*(h.index&0xFFFF);
    if(rd<u32>(item+4)&0x10200000u) return false; // Unreachable | Garbage, UE5.7
    // UE5.7 places FlagsAndRefCount at +0, Object at +8, Serial at +0x10.
    // The previous helper compared expected against FlagsAndRefCount (+0),
    // which rejected every live object. Serial +0x10 in the guarded native
    // allocator confirms this is the unpacked (8-byte Object) layout.
    return rd<u64>(item+8)==expected && rd<u32>(item+0x10)==h.serial;
}
static int context_status() {
    u64 objects[]={capture.widget,capture.gm,capture.active,capture.temp,capture.before,capture.piece_class};
    if(capture.home) {objects[2]=capture.temp;objects[3]=capture.before;objects[4]=capture.piece_class;objects[5]=capture.widget;}
    for(int i=0;i<6;++i) if(!weak_valid(weak_objects[i],objects[i])) return -61-i;
    return 1;
}
// Library-scoped factory: same native UPiece construction and complete save
// loader as stock, but omit UObservableCollection::Add (Creative build list).
// All unarmed/other-widget downloads retain the original factory unchanged.
static u64 receive_factory(u64 state,u64 data,u8 demo,u64 widget) {
    if(widget!=capture.widget || (capture.status!=1 && capture.status!=-9))
        return original_factory(state,data,demo);
    if(!ptr(state)||!ptr(data)||demo || GetCurrentThreadId()!=capture.thread ||
       GetTickCount64()>capture.deadline || context_status()!=1) return 0;
    u64 piece=0;
    __try {
        piece=create_piece(state);
        if(!ptr(piece) || rd<u64>(piece+0x10)!=capture.piece_class ||
           (rd<u32>(piece+8)&0x40000000u)) return 0;
        load_piece(piece,data);
    } __except(1) {return 0;}
    // receive() takes ownership in temp.Piece immediately after this callback
    // returns. Returning zero on failure is rejected there, never auto-placed.
    return piece;
}
// Called on the original callback thread. A cancelled request remains scoped
// until its completion arrives, so a late HTTP success cannot auto-place.
static void receive(u64 gm,u64 piece,u64 widget) {
    if(widget!=capture.widget || (capture.status!=1 && capture.status!=-9)) {
        original(gm,piece); return;
    }
    if(capture.status==-9) { capture.status=-8; return; }
    if(GetCurrentThreadId()!=capture.thread || GetTickCount64()>capture.deadline) {
        capture.status=-7; return;
    }
    if(capture.home) {
        if(gm!=capture.gm||!ptr(piece)||context_status()!=1||
           rd<u64>(gm+0x448)!=capture.active||rd<u64>(capture.temp+0x10)!=capture.before||
           rd<u64>(capture.temp+0x328)||rd<u64>(piece+0x10)!=capture.piece_class||
           (rd<u32>(piece+8)&0x40000000u)) {capture.status=-5;return;}
        // This widget is retained in the modal's hidden child tree. Its reflected
        // BoundPiece UPROPERTY owns the result without any Forge actor or entry.
        wr<u64>(capture.temp+0x328,piece);capture.status=2;return;
    }
    if(gm!=capture.gm || !ptr(piece) || context_status()!=1 ||
       rd<u64>(gm+0x448)!=capture.active ||
       rd<u64>(capture.temp+0x3D8)!=capture.before ||
       rd<u64>(capture.active+0x3D8)!=capture.before ||
       rd<u64>(piece+0x10)!=capture.piece_class ||
       (rd<u32>(piece+8)&0x40000000u)) {
        capture.status=-5; return;
    }
    wr<u64>(capture.temp+0x3D8,piece);
    capture.status=2;
}
static int image_guard() {
    image=(u64)GetModuleHandleW(0);
    if(!ptr(image) || rd<unsigned short>(image)!=0x5A4D) return -2;
    u64 pe=image+rd<u32>(image+0x3C);
    if(rd<u32>(pe)!=0x4550 || rd<u32>(pe+24+56)!=0x090A2000) return -3;
    if(!same(image+0x4635E20,callback_prologue,sizeof(callback_prologue)) ||
       !same(image+0x1499250,weak_assign_prologue,sizeof(weak_assign_prologue)) ||
       !same(image+0x1499266,weak_array_reference,sizeof(weak_array_reference)) ||
       !same(image+0x147AC99,weak_serial_layout,sizeof(weak_serial_layout)) ||
       !same(image+0x147AC76,object_array_layout,sizeof(object_array_layout)) ||
       !same(image+0x4635E51,callback_widget,sizeof(callback_widget)) ||
       !same(image+0x463602F,call_arguments,sizeof(call_arguments)) ||
       !same(image+0x45A80D0,enter_prologue,sizeof(enter_prologue)) ||
       !same(image+0x45B7400,seam_prologue,sizeof(seam_prologue)) ||
       !same(image+0x45B74AF,piece_store,sizeof(piece_store)) ||
       !same(image+0x45A8289,forge_store,sizeof(forge_store))) return -4;
    if(!same(image+0x4636035,installed?patch:call_bytes,5) ||
       !same(image+0x4635FD9,installed?factory_patch:factory_call,5) ||
       !same(image+0x4635FCE,factory_arguments,sizeof(factory_arguments)) ||
       !same(image+0x45A3890,factory_prologue,sizeof(factory_prologue)) ||
       !same(image+0x45939F0,new_piece_prologue,sizeof(new_piece_prologue)) ||
       !same(image+0x45BA180,load_piece_prologue,sizeof(load_piece_prologue)) ||
       !same(image+0x45A38C1,factory_add_inventory,sizeof(factory_add_inventory))) return -4;
    object_array=image+0x86523D0;
    return 1;
}
static bool write_call(u64 site,const u8* bytes) {
    u32 old=0;
    if(!VirtualProtect((void*)site,5,0x40,&old)) return false;
    for(u32 i=0;i<5;++i) wr<u8>(site+i,bytes[i]);
    u32 ignored=0;VirtualProtect((void*)site,5,old,&ignored);
    FlushInstructionCache((void*)-1,(void*)site,5);
    return same(site,bytes,5);
}
static void make_call(u8* bytes,u64 site,u64 target) {
    bytes[0]=0xE8;
    int delta=(int)((i64)target-(i64)(site+5));
    for(int i=0;i<4;++i)bytes[1+i]=(u8)((u32)delta>>(8*i));
}
static void make_relay(u64 at,u8 register_code,u64 target) {
    // mov r8/r9,rdi; mov rax,imm64; jmp rax. Preserve stock arguments.
    wr<u8>(at,0x49);wr<u8>(at+1,0x89);wr<u8>(at+2,register_code);
    wr<u8>(at+3,0x48);wr<u8>(at+4,0xB8);wr<u64>(at+5,target);
    wr<u8>(at+13,0xFF);wr<u8>(at+14,0xE0);
}
static int install() {
    int guard=image_guard();if(guard!=1||installed)return guard;
    u64 site=image+0x4636035,factory_site=image+0x4635FD9;
    for(u64 distance=0x10000;distance<0x70000000;distance+=0x10000) {
        for(int direction=0;direction<2;++direction) {
            u64 where=(site&~0xFFFFull)+(direction?distance:0-distance);
            relay=(u64)VirtualAlloc((void*)where,0x1000,0x3000,0x04);
            if(relay)break;
        }
        if(relay)break;
    }
    if(!relay)return -10;
    make_relay(relay,0xF8,(u64)&receive);
    make_relay(relay+32,0xF9,(u64)&receive_factory);
    u32 old=0;
    if(!VirtualProtect((void*)relay,0x1000,0x20,&old))return -11;
    FlushInstructionCache((void*)-1,(void*)relay,47);
    original=(Enter)(image+0x45A80D0);
    original_factory=(Factory)(image+0x45A3890);
    create_piece=(NewPiece)(image+0x45939F0);
    load_piece=(LoadPiece)(image+0x45BA180);
    make_call(patch,site,relay);make_call(factory_patch,factory_site,relay+32);
    if(!write_call(factory_site,factory_patch))return -12;
    if(!write_call(site,patch)) {
        write_call(factory_site,factory_call);
        write_call(site,call_bytes);
        return -12;
    }
    installed=true;
    return image_guard();
}
extern "C" __declspec(dllexport) int pcl_download_arm(void* L) {
    u64 widget=0,gm=0,active=0,temp=0,before=0,piece_class=0;
    if(!arg(L,1,widget)||!arg(L,2,gm)||!arg(L,3,active)||
       !arg(L,4,temp)||!arg(L,5,before)||!arg(L,6,piece_class)) return result(L,-1);
    if(capture.status==1 || capture.status==-9) return result(L,-6);
    int status=install(); if(status!=1) return result(L,status);
    if(!ptr(widget)||!ptr(gm)||!ptr(active)||!ptr(temp)||!ptr(before)||!ptr(piece_class)||active==temp)
        return result(L,-5);
    if(rd<u64>(gm+0x448)!=active) return result(L,-52);
    if(rd<u64>(active+0x3D8)!=before) return result(L,-53);
    if(rd<u64>(temp+0x3D8)!=before) return result(L,-54);
    if(rd<u64>(before+0x10)!=piece_class) return result(L,-55);
    if(rd<u64>(temp+0x10)!=rd<u64>(active+0x10)) return result(L,-56);
    capture={widget,gm,active,temp,before,piece_class,GetTickCount64()+120000,GetCurrentThreadId(),1};
    u64 objects[]={widget,gm,active,temp,before,piece_class};
    typedef void (*AssignWeak)(Weak*,u64*);
    for(int i=0;i<6;++i) ((AssignWeak)(image+0x1499250))(&weak_objects[i],&objects[i]);
    int weak_status=context_status();
    if(weak_status!=1) { capture.status=weak_status; return result(L,weak_status); }
    return result(L,1);
}
extern "C" __declspec(dllexport) int pcl_download_status(void* L) { return result(L,capture.status); }
extern "C" __declspec(dllexport) int pcl_download_probe(void* L) { return result(L,image_guard()); }
extern "C" __declspec(dllexport) int pcl_download_cancel(void* L) {
    if(capture.status==1) capture.status=-9;
    return result(L,capture.status);
}
extern "C" __declspec(dllexport) int pcl_download_rebuild(void* L) {
    u64 temp=0,piece=0;
    if(!arg(L,1,temp)||!arg(L,2,piece)) return result(L,-1);
    int guard=image_guard(); if(guard!=1) return result(L,guard);
    if(capture.status!=2 || temp!=capture.temp || !ptr(piece) || context_status()!=1 ||
       rd<u64>(temp+0x3D8)!=piece || rd<u64>(piece+0x10)!=capture.piece_class ||
       GetCurrentThreadId()!=capture.thread) return result(L,-5);
    // Capture is consumed BEFORE construction: never run the seam twice.
    capture.status=3;
    ((Enter)(image+0x45B7400))(temp,piece);
    return result(L,1);
}
extern "C" int __stdcall DllMain(void*,unsigned long,void*) { return 1; }

// Stock UWPieceInventoryEntry::CreateBoundPieceCopy reads BoundPiece at +328.
// This is a layout guard only; that method is never invoked by the library.
static const u8 home_bound_layout[]={0x48,0x83,0xB9,0x28,0x03,0x00,0x00,0x00};
extern "C" __declspec(dllexport) int pcl_download_arm_home(void* L) {
    u64 widget=0,gm=0,holder=0,holderclass=0,piececlass=0;
    if(!arg(L,1,widget)||!arg(L,2,gm)||!arg(L,3,holder)||!arg(L,4,holderclass)||!arg(L,5,piececlass))return result(L,-1);
    if(capture.status==1||capture.status==-9)return result(L,-6);
    int status=install();if(status!=1)return result(L,status);
    if(!same(image+0x461A8C2,home_bound_layout,sizeof(home_bound_layout)))return result(L,-70);
    if(!ptr(widget)||!ptr(gm)||!ptr(holder)||!ptr(holderclass)||!ptr(piececlass))return result(L,-5);
    if(rd<u64>(holder+0x10)!=holderclass||rd<u64>(holder+0x328))return result(L,-71);
    capture={widget,gm,rd<u64>(gm+0x448),holder,holderclass,piececlass,GetTickCount64()+120000,GetCurrentThreadId(),1,true};
    u64 objects[]={widget,gm,holder,holderclass,piececlass,widget};
    typedef void (*AssignWeak)(Weak*,u64*);
    for(int i=0;i<6;++i)((AssignWeak)(image+0x1499250))(&weak_objects[i],&objects[i]);
    int valid=context_status();if(valid!=1){capture.status=valid;return result(L,valid);}
    return result(L,1);
}

extern "C" __declspec(dllexport) int pcl_download_failed(void* L) {
    u64 widget=0;if(!arg(L,1,widget)||widget!=capture.widget)return result(L,-1);
    if(capture.status==1||capture.status==-9)capture.status=-8;
    return result(L,capture.status);
}
