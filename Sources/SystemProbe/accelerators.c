#include "SystemProbe.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/sysctl.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>

// Driver observations, not an occupancy API. Each returned row is a live GPU
// user client; Swift differences stable registry identities, never PID totals.
static int unsigned_value(CFTypeRef value, uint64_t *out) {
 int64_t n;
 if(!value || CFGetTypeID(value)!=CFNumberGetTypeID() || !CFNumberGetValue(value,kCFNumberSInt64Type,&n) || n<0) return 0;
 *out=(uint64_t)n;return 1;
}
int tg_gpu_clients(TGGPUClient **output, int *available) {
 *output=NULL;*available=0;
 io_iterator_t accelerators=0;
 if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AGXAccelerator"),&accelerators)!=KERN_SUCCESS) return 0;
 int count=0,capacity=128,found=0,complete=1;
 TGGPUClient *rows=calloc(capacity,sizeof(*rows));
 if(!rows){IOObjectRelease(accelerators);return 0;}
 io_service_t parent;
 while((parent=IOIteratorNext(accelerators))) {
  found=1;io_iterator_t children=0;
  if(IORegistryEntryGetChildIterator(parent,kIOServicePlane,&children)!=KERN_SUCCESS){complete=0;IOObjectRelease(parent);continue;}
  io_registry_entry_t child;
  while((child=IOIteratorNext(children))) {
   if(count>=4096){complete=0;IOObjectRelease(child);break;}
   if(IOObjectConformsTo(child,"IOUserClient")) {
    CFMutableDictionaryRef properties=NULL;
    if(IORegistryEntryCreateCFProperties(child,&properties,kCFAllocatorDefault,0)==KERN_SUCCESS && properties) {
     CFTypeRef owner=CFDictionaryGetValue(properties,CFSTR("IOUserClientCreator"));
     CFTypeRef usage=CFDictionaryGetValue(properties,CFSTR("AppUsage"));
     char text[256]={0};int pid=0;uint64_t id=0,total=0,last=0;
     if(owner && CFGetTypeID(owner)==CFStringGetTypeID()) CFStringGetCString(owner,text,sizeof(text),kCFStringEncodingUTF8);
     if(sscanf(text,"pid %d,",&pid)==1 && pid>0 && usage && CFGetTypeID(usage)==CFArrayGetTypeID() && IORegistryEntryGetRegistryEntryID(child,&id)==KERN_SUCCESS) {
      CFIndex n=CFArrayGetCount(usage);int valid=n<=4096;
      for(CFIndex i=0;i<n && valid;i++) {
       CFTypeRef entry=CFArrayGetValueAtIndex(usage,i);uint64_t ns=0,submitted=0;
       if(!entry || CFGetTypeID(entry)!=CFDictionaryGetTypeID() || !unsigned_value(CFDictionaryGetValue(entry,CFSTR("accumulatedGPUTime")),&ns) || UINT64_MAX-total<ns){valid=0;break;}
       total+=ns;
       if(unsigned_value(CFDictionaryGetValue(entry,CFSTR("lastSubmittedTime")),&submitted) && submitted>last) last=submitted;
      }
      if(valid) {
       if(count==capacity) {
        int next=capacity*2;TGGPUClient *grown=realloc(rows,next*sizeof(*rows));
        if(!grown){complete=0;IOObjectRelease(child);CFRelease(properties);break;}
        rows=grown;capacity=next;
       }
       rows[count++]=(TGGPUClient){.entry=id,.pid=pid,.nanoseconds=total,.last_submitted_ns=last,.contexts=(uint32_t)n};
      }
     }
     CFRelease(properties);
    }
   }
   IOObjectRelease(child);
  }
  IOObjectRelease(children);IOObjectRelease(parent);
 }
 IOObjectRelease(accelerators);
 *available=found && complete && count>0;*output=rows;return count;
}

// macOS 27 coalition ABI, checked against Apple's XNU mach/coalition.h and
// proc_info_private.h. Time belongs to a RESOURCE COALITION, not each PID.
// See docs/accelerator-attribution.md. Never decode another OS's layout.
static pthread_once_t coalition_once=PTHREAD_ONCE_INIT;
static int coalition_enabled;
static int (*coalition_usage)(uint64_t,void *,size_t);
static mach_timebase_info_data_t timebase;
static void coalition_init(void) {
 char version[32]={0};size_t size=sizeof(version);
 sysctlbyname("kern.osproductversion",version,&size,NULL,0);
 coalition_usage=(int (*)(uint64_t,void *,size_t))dlsym(RTLD_DEFAULT,"coalition_info_resource_usage");
 coalition_enabled=strncmp(version,"27.",3)==0 && coalition_usage && mach_timebase_info(&timebase)==KERN_SUCCESS && timebase.denom>0;
}
int tg_ane_accounting_supported(void) { pthread_once(&coalition_once,coalition_init);return coalition_enabled; }
static int decode_coalition_time(const uint64_t *words,size_t written,uint32_t numer,uint32_t denom,uint64_t *ns) {
 const uint64_t sentinel=UINT64_C(0xa5a5a5a5a5a5a5a5);
 if((written!=45 && written!=50) || words[23]!=7 || words[38]==sentinel || !denom)return 0;
 __uint128_t value=(__uint128_t)words[38]*numer/denom;
 if(value>UINT64_MAX)return 0;
 *ns=(uint64_t)value;return 1;
}
static int coalition_time(uint64_t id,uint64_t *ns) {
 const uint64_t sentinel=UINT64_C(0xa5a5a5a5a5a5a5a5);
 uint64_t words[64];for(int i=0;i<64;i++)words[i]=sentinel;
 if(coalition_usage(id,words,sizeof(words))!=0)return 0;
 size_t written=64;while(written>0 && words[written-1]==sentinel)written--;
 return decode_coalition_time(words,written,timebase.numer,timebase.denom,ns);
}
void tg_ane_process_groups(TGProcess *rows,int count) {
 if(count<=0 || !tg_ane_accounting_supported())return;
 size_t capacity=16;while(capacity<(size_t)count*2)capacity*=2;
 typedef struct {uint64_t id,ns;int valid;} Cached;
 Cached *cache=calloc(capacity,sizeof(*cache));if(!cache)return;
 for(int i=0;i<count;i++) {
  // PROC_PIDCOALITIONINFO=20: two coalition IDs followed by three reserved words.
  uint64_t ids[5]={0};
  if(proc_pidinfo(rows[i].pid,20,0,ids,sizeof(ids))!=sizeof(ids) || ids[0]==0)continue;
  rows[i].ane_group=ids[0];size_t slot=(ids[0]*UINT64_C(11400714819323198485))&(capacity-1);
  while(cache[slot].id && cache[slot].id!=ids[0])slot=(slot+1)&(capacity-1);
  if(!cache[slot].id){cache[slot].id=ids[0];cache[slot].valid=coalition_time(ids[0],&cache[slot].ns);}
  rows[i].ane_valid=cache[slot].valid;rows[i].ane_nanoseconds=cache[slot].ns;
 }
 free(cache);
}
