// Diagnostic LD_PRELOAD shim: does not replace the installed SDK.
// Delay the AXI plugin's staging-buffer read before its cache synchronization.
#include <dlfcn.h>
#include <unistd.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <atomic>
static std::atomic<unsigned long> calls{0};
extern "C" void intercepted_read(const void*,char*,uint64_t,uint64_t) asm("_ZNK6icraft3xrt8MemChunk4readEPcmm");
extern "C" void intercepted_read(const void* self,char* dest,uint64_t offset,uint64_t size){
    using Fn=void(*)(const void*,char*,uint64_t,uint64_t);
    static auto real=reinterpret_cast<Fn>(dlsym(RTLD_NEXT,"_ZNK6icraft3xrt8MemChunk4readEPcmm"));
    static unsigned delay=[](){const char* e=std::getenv("FMQL_DMA_DELAY_US");return e?unsigned(std::atoi(e)):0U;}();
    if(!real){std::fputs("DMA_SHIM symbol missing\n",stderr);_exit(127);}
    Dl_info info{};
    if(dladdr(__builtin_return_address(0),&info)&&info.dli_fname&&std::strstr(info.dli_fname,"libaxizg330aiu")){
        ++calls;if(delay)usleep(delay);
    }
    real(self,dest,offset,size);
}
__attribute__((destructor)) static void report(){std::fprintf(stderr,"DMA_SHIM staging_reads=%lu\n",calls.load());}
