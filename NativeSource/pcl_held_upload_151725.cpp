// 15.17.25: isolated held-tree upload snapshot; no code patches or mesh-buffer reads.
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
static const u8 guard_tree[]={0x40,0x55,0x53,0x56,0x57,0x41,0x54,0x41,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0xac,0x24,0x8};
static const u8 guard_send[]={0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7c,0x24,0x20,0x55,0x41,0x56};
static const u8 guard_weak[]={0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b};
static const u8 guard_send_piece[]={0x48,0x8b,0x89,0x28,0x3,0x0,0x0,0x48};
static const u8 guard_index_write[]={0x89,0xb3,0xb4,0x2,0x0,0x0,0x48,0x8b};
static const u8 guard_tree_call[]={0xe8,0x93,0xfb,0xff,0xff,0x4c,0x8b,0x9b};
static const u8 guard_copy[]={0x48,0x89,0x5c,0x24,0x8,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x41,0x56};
static u64 image=0;
static bool busy=false;
static u32 owner_thread=0;
static u64 actor_addresses[6000];
static u32 actor_indices[6000];
static bool live(u64 p) {
    if(!ptr(p)) return false;
    struct Weak {u32 index,serial;} weak={};
    ((void(*)(Weak*,u64*))(image+0x1499250))(&weak,&p);
    const u64 objects=image+0x86523D0;
    u32 index=weak.index;
    if(index>=rd<u32>(objects+0x24)) return false;
    u64 chunks=rd<u64>(objects+0x10);
    if(!ptr(chunks)) return false;
    u64 chunk=rd<u64>(chunks+8ull*(index>>16));
    if(!ptr(chunk)) return false;
    u64 item=chunk+24ull*(index&0xFFFF);
    return rd<u64>(item+8)==p && !(rd<u32>(item+4)&0x10200000u) && weak.serial!=0 && rd<u32>(item+0x10)==weak.serial;
}
static int guard() {
    image=(u64)GetModuleHandleW(0);
    if(!ptr(image)||rd<unsigned short>(image)!=0x5A4D) return -2;
    u64 pe=image+rd<u32>(image+0x3C);
    if(rd<u32>(pe)!=0x4550||rd<u32>(pe+24+56)!=0x090A2000) return -3;
    if(!same(image+0x45C6F20,guard_tree,sizeof(guard_tree)) ||
       !same(image+0x4649C10,guard_send,sizeof(guard_send)) ||
       !same(image+0x1499250,guard_weak,sizeof(guard_weak)) ||
       !same(image+0x4649C54,guard_send_piece,sizeof(guard_send_piece)) ||
       !same(image+0x45C6FB0,guard_index_write,sizeof(guard_index_write)) ||
       !same(image+0x45C7388,guard_tree_call,sizeof(guard_tree_call)) ||
       !same(image+0x4540C50,guard_copy,sizeof(guard_copy))) return -4;
    if(!owner_thread) owner_thread=GetCurrentThreadId();
    if(owner_thread!=GetCurrentThreadId()) return -5;
    return 1;
}
extern "C" __declspec(dllexport) int pcl_upload_probe(void* L) {return result(L,guard());}
extern "C" __declspec(dllexport) int pcl_upload_snapshot(void* L) {
    u64 forge=0,piece=0,root=0,count=0;
    if(!arg(L,1,forge)||!arg(L,2,piece)||!arg(L,3,root)||!arg(L,4,count)) return result(L,-1);
    int status=guard();if(status!=1) return result(L,status);
    if(busy||count<1||count>6000) return result(L,-6);
    if(!live(forge)||!live(piece)||!live(root)) return result(L,-7);
    u64 source=rd<u64>(forge+0x3D8);
    if(!live(source)||source==piece||rd<u64>(source+0x10)!=rd<u64>(piece+0x10)) return result(L,-8);
    u64 d=piece+0x30;
    if(rd<u32>(d+0xA0)!=0) return result(L,-9); // fresh destination only
    for(u32 i=0;i<(u32)count;++i) {
        u64 actor=0;if(!arg(L,5+i,actor)||!live(actor)) return result(L,-10);
        for(u32 j=0;j<i;++j) if(actor_addresses[j]==actor) return result(L,-11);
        actor_addresses[i]=actor;actor_indices[i]=rd<u32>(actor+0x2B4);
    }
    if(actor_addresses[0]!=root||root==rd<u64>(forge+0x320)) return result(L,-12);
    busy=true;
    __try {
        __try {
            // Copy the game's complete blade/ability data with its own deep-copy
            // operator. The temporary source view excludes both active-Forge
            // attachment arrays, whose indices refer to a different part tree.
            __declspec(align(16)) u8 view[0x100];
            for(u32 i=0;i<0x100;++i) view[i]=rd<u8>(source+0x30+i);
            for(u32 i=0x88;i<0xA8;++i) view[i]=0;
            ((void(*)(u64,const void*))(image+0x4540C50))(d,view);
            wr<u32>(d+0x68,0);
            ((void(*)(u64,u64,u64,int,int,u64,u64))(image+0x45C6F20))(
                forge,d,root,-1,-1,image+0x838B398,image+0x838B5A0);
            u32 n=rd<u32>(d+0xA0);u64 parts=rd<u64>(d+0x98);
            status=(n==count && ptr(parts))?int(n):-13;
            if(status>0) for(u32 i=0;i<n;++i) wr<u8>(parts+0x120ull*i+0x2C,0);
        } __except(1) {status=-14;}
    } __finally {
        for(u32 i=0;i<(u32)count;++i) if(live(actor_addresses[i])) wr<u32>(actor_addresses[i]+0x2B4,actor_indices[i]);
        busy=false;
    }
    return result(L,status);
}
extern "C" __declspec(dllexport) int pcl_upload_send(void* L) {
    u64 ui=0,active=0,host=0,piece=0;
    if(!arg(L,1,ui)||!arg(L,2,active)||!arg(L,3,host)||!arg(L,4,piece)) return result(L,-1);
    int status=guard();if(status!=1) return result(L,status);
    if(busy||!live(ui)||!live(active)||!live(host)||!live(piece)) return result(L,-7);
    if(rd<u64>(ui+0x328)!=active || rd<u64>(host+0x3D8)!=piece || host==active ||
       rd<u64>(active+0x3D8)==piece || rd<u32>(piece+0xD0)<1) return result(L,-15);
    busy=true;
    __try {
        __try {
            // This native post-preview continuation copies FPieceSaveData to
            // JSON synchronously, then starts HTTP. Restore the UI's live Forge
            // binding before yielding; actors and active Piece never change.
            wr<u64>(ui+0x328,host);
            ((void(*)(u64))(image+0x4649C10))(ui);
            status=1;
        } __except(1) {status=-16;}
    } __finally {wr<u64>(ui+0x328,active);busy=false;}
    return result(L,status);
}
