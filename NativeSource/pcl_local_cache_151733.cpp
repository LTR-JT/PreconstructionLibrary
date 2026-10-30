// 15.17.26: native one-build SaveGame cache; isolated offline reconstruction.
#include "pcl_held_upload_151725.cpp"
static const u8 cache_save[]={0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x6c,0x24,0x20,0x48,0x89,0x54,0x24,0x10,0x56,0x57,0x41,0x56,0x48,0x83,0xec,0x40,0x48};
static const u8 cache_grow[]={0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7c,0x24,0x20,0x41,0x54,0x41,0x56,0x41,0x57,0x48,0x83,0xec,0x30,0x41,0x8b,0x31,0x4d};
static const u8 cache_rebuild[]={0x48,0x8b,0xc4,0x48,0x89,0x58,0x10,0x48,0x89,0x70,0x18,0x48,0x89,0x78,0x20,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0x68,0xc8};
static const u8 cache_decode[]={0x48,0x89,0x5c,0x24,0x8,0x48,0x89,0x6c,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xec,0x30,0x41,0xf,0xb6,0xe8};
static const u8 cache_load[]={0x48,0x89,0x5c,0x24,0x10,0x48,0x89,0x6c,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x57,0x48,0x83,0xec,0x20,0x48,0x8b,0xd9,0x48,0x8b,0xfa,0x48,0x83,0xc1,0x30,0xe8,0xad};
static int cache_guard() {
    int status=guard();if(status!=1)return status;
    if(!same(image+0x45A39E0,cache_save,sizeof(cache_save)) ||
       !same(image+0x10EE5E0,cache_grow,sizeof(cache_grow)) ||
       !same(image+0x45B7400,cache_rebuild,sizeof(cache_rebuild)) ||
       !same(image+0x11DB810,cache_decode,sizeof(cache_decode)) ||
       !same(image+0x45BA180,cache_load,sizeof(cache_load)))return -26;
    return 1;
}
extern "C" __declspec(dllexport) int pcl_cache_probe(void* L) {return result(L,cache_guard());}
extern "C" __declspec(dllexport) int pcl_cache_store(void* L) {
    u64 save=0,piece=0,saveclass=0,piececlass=0;
    if(!arg(L,1,save)||!arg(L,2,piece)||!arg(L,3,saveclass)||!arg(L,4,piececlass))return result(L,-1);
    int status=cache_guard();if(status!=1)return result(L,status);
    if(busy||!live(save)||!live(piece)||!live(saveclass)||!live(piececlass))return result(L,-7);
    if(rd<u64>(save+0x10)!=saveclass||rd<u64>(piece+0x10)!=piececlass ||
       rd<u64>(save+0x30)||rd<u64>(save+0x38)||rd<u32>(piece+0xD0)<1 || rd<u32>(piece+0xD0)>6000)return result(L,-27);
    busy=true;
    __try {
        // Engine TArray grow: element size, alignment, allocator, capacity.
        // Num stays zero until GetSaveData constructs the complete element.
        ((int(*)(u32,u32,u64,u64))(image+0x10EE5E0))(0x1A8,8,save+0x30,save+0x3C);
        u64 data=rd<u64>(save+0x30);
        if(!ptr(data)||rd<u32>(save+0x3C)<1)status=-28;
        else {
            ((u64(*)(u64,u64))(image+0x45A39E0))(piece,data);
            wr<u32>(save+0x38,1);status=1;
        }
    } __except(1){status=-29;}
    busy=false;return result(L,status);
}
extern "C" __declspec(dllexport) int pcl_cache_restore(void* L) {
    u64 save=0,piece=0,saveclass=0,piececlass=0;
    if(!arg(L,1,save)||!arg(L,2,piece)||!arg(L,3,saveclass)||!arg(L,4,piececlass))return result(L,-1);
    int status=cache_guard();if(status!=1)return result(L,status);
    if(busy||!live(save)||!live(piece)||!live(saveclass)||!live(piececlass))return result(L,-7);
    u64 data=rd<u64>(save+0x30);
    if(rd<u64>(save+0x10)!=saveclass||rd<u64>(piece+0x10)!=piececlass||
       rd<u32>(save+0x38)!=1||!ptr(data)||rd<u32>(piece+0xD0)!=0)return result(L,-30);
    u32 count=rd<u32>(data+0xA0);
    if(count<1||count>6000||!ptr(rd<u64>(data+0x98)))return result(L,-31);
    busy=true;
    __try {
        u32 length=rd<u32>(data+0x180);
        if(length>32*1024*1024 || (length && !ptr(rd<u64>(data+0x178))))status=-37;
        else {
            // Same full UPiece save-data loader called by the game's download
            // factory at 45A38BC, including native WDD fixup and preview decode.
            ((void(*)(u64,u64))(image+0x45BA180))(piece,data);
            status=(rd<u32>(piece+0xD0)==count)?1:-32;
        }
    } __except(1){status=-33;}
    busy=false;return result(L,status);
}
extern "C" __declspec(dllexport) int pcl_cache_rebuild(void* L) {
    u64 host=0,piece=0,active=0,gm=0;
    if(!arg(L,1,host)||!arg(L,2,piece)||!arg(L,3,active)||!arg(L,4,gm))return result(L,-1);
    int status=cache_guard();if(status!=1)return result(L,status);
    if(busy||!live(host)||!live(piece)||!live(active)||!live(gm))return result(L,-7);
    if(host==active||rd<u64>(host+0x10)!=rd<u64>(active+0x10)||rd<u64>(host+0x3D8)!=piece||
       rd<u64>(active+0x3D8)==piece||rd<u64>(gm+0x448)!=active)return result(L,-34);
    busy=true;
    __try {((void(*)(u64,u64))(image+0x45B7400))(host,piece);status=1;}
    __except(1){status=-35;}
    busy=false;return result(L,status);
}

// Read the four native fixed-array ALineRenderer pointers. The SDK property
// has ArrayDim=4, not a TArray header; never interpret it as dynamic array data.
extern "C" __declspec(dllexport) int pcl_cache_lines(void* L) {
    u64 interaction=0,host=0,frontend=0;
    int status=cache_guard();u64 lines[4]={};
    if(!arg(L,1,interaction)||!arg(L,2,host)||!arg(L,3,frontend))status=-1;
    if(status==1) {
        __try {
            if(!live(interaction)||!live(host)||!live(frontend) ||
               rd<u64>(interaction+0x30)!=host || rd<u64>(interaction+0x38)!=frontend ||
               rd<u64>(host+0x2F8)!=frontend)status=-38;
            else for(u32 i=0;i<4;++i) {
                u64 actor=rd<u64>(interaction+0xC0+8ull*i);
                if(live(actor))lines[i]=actor;
            }
        } __except(1){status=-39;}
    }
    result(L,status);
    for(u32 i=0;i<4;++i)result(L,status==1?(i64)lines[i]:0);
    return 5;
}

// Read-only UObject identity query. Unlike UE4SS IsValid, every dereference is
// protected by SEH. No StaticFindObject/path lookup and no UObject mutation.
extern "C" __declspec(dllexport) int pcl_cache_valid(void* L) {
    u64 object=0;
    int status=guard();
    if(status!=1)return result(L,status);
    if(!arg(L,1,object)||!ptr(object))return result(L,0);
    i64 serial=0;
    __try {
        const u64 objects=image+0x86523D0;
        u32 index=rd<u32>(object+0xC); // verified UObjectBase::InternalIndex_Private
        if(index<rd<u32>(objects+0x24)) {
            u64 chunks=rd<u64>(objects+0x10);
            if(ptr(chunks)) {
                u64 chunk=rd<u64>(chunks+8ull*(index>>16));
                if(ptr(chunk)) {
                    u64 item=chunk+24ull*(index&0xFFFF);
                    if(rd<u64>(item+8)==object && !(rd<u32>(item+4)&0x10200000u)) {
                        serial=rd<u32>(item+0x10);
                        // Assign a serial only for a confirmed live object,
                        // through the same engine API used by existing bridges.
                        if(!serial) {
                            struct Weak {u32 index,serial;} weak={};
                            ((void(*)(Weak*,u64*))(image+0x1499250))(&weak,&object);
                            serial=weak.serial;
                        }
                    }
                }
            }
        }
    } __except(1){serial=0;}
    return result(L,serial);
}

extern "C" __declspec(dllimport) int __stdcall OpenClipboard(void*);
extern "C" __declspec(dllimport) int __stdcall CloseClipboard();
extern "C" __declspec(dllimport) int __stdcall EmptyClipboard();
extern "C" __declspec(dllimport) void* __stdcall SetClipboardData(u32,void*);
extern "C" __declspec(dllimport) void* __stdcall GlobalAlloc(u32,u64);
extern "C" __declspec(dllimport) void* __stdcall GlobalLock(void*);
extern "C" __declspec(dllimport) int __stdcall GlobalUnlock(void*);
extern "C" __declspec(dllimport) void* __stdcall GlobalFree(void*);
extern "C" __declspec(dllimport) void* __stdcall GetActiveWindow();
extern "C" __declspec(dllexport) int pcl_cache_copy_word(void* L) {
    int status=guard();if(status!=1)return result(L,status);
    u64 length=0;if(!arg(L,1,length)||length<5||length>160)return result(L,-1);
    unsigned short text[161]={};u32 hyphens=0;
    for(u32 i=0;i<length;++i) {
        u64 byte=0;if(!arg(L,i+2,byte)||!((byte>='a'&&byte<='z')||(byte>='A'&&byte<='Z')||byte=='-'))return result(L,-1);
        text[i]=(unsigned short)byte;if(byte=='-')++hyphens;
    }
    if(hyphens!=2)return result(L,-1);
    void* memory=GlobalAlloc(2,(length+1)*2);if(!memory)return result(L,-40);
    unsigned short* output=(unsigned short*)GlobalLock(memory);
    if(!output){GlobalFree(memory);return result(L,-40);}
    for(u32 i=0;i<=length;++i)output[i]=text[i];
    GlobalUnlock(memory);
    // A real application window owns clipboard data; NULL ownership after
    // EmptyClipboard would cause SetClipboardData to fail on Windows.

    void* window=GetActiveWindow();
    if(!window||!OpenClipboard(window)){GlobalFree(memory);return result(L,-41);}
    bool copied=EmptyClipboard()&&SetClipboardData(13,memory)!=0; // CF_UNICODETEXT
    CloseClipboard();if(!copied)GlobalFree(memory);
    return result(L,copied?1:-42);
}
