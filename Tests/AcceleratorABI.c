// Compile the implementation into this test so the ABI decoder stays private.
#include "../Sources/SystemProbe/accelerators.c"
#include <assert.h>
#include <unistd.h>
#include <stddef.h>
#include <sys/resource.h>
int main(void) {
 uint64_t words[64]={0},ns=123;words[23]=7;words[38]=24000000;
 assert(decode_coalition_time(words,45,125,3,&ns) && ns==1000000000);
 assert(decode_coalition_time(words,50,1,1,&ns) && ns==24000000);
 for(size_t count=0;count<=64;count++) if(count!=45 && count!=50) assert(!decode_coalition_time(words,count,1,1,&ns));
 words[23]=8;assert(!decode_coalition_time(words,50,1,1,&ns));words[23]=7;
 words[38]=0;assert(decode_coalition_time(words,50,1,1,&ns) && ns==0);
 assert(!decode_coalition_time(words,50,1,0,&ns));
 words[38]=UINT64_MAX;assert(!decode_coalition_time(words,50,2,1,&ns));
 words[38]=UINT64_C(0xa5a5a5a5a5a5a5a5);assert(!decode_coalition_time(words,50,1,1,&ns));
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 270000
 _Static_assert(offsetof(struct rusage_info_v6,ri_neural_footprint)==368,"Review neural memory ABI");
#endif
 for(int scan=0;scan<3;scan++) {
  TGGPUClient *clients=NULL;int available=0;
  int count=tg_gpu_clients(&clients,&available);
  assert(count>=0 && count<=4096 && (available==0 || available==1));
  for(int i=0;i<count;i++) {
   assert(clients[i].pid>0 && clients[i].entry!=0 && clients[i].contexts<=4096);
   for(int j=0;j<i;j++)assert(clients[i].entry!=clients[j].entry);
  }
  free(clients);
 }
 TGProcess process={0};process.pid=getpid();tg_ane_process_groups(&process,1);
 if(!tg_ane_accounting_supported())assert(!process.ane_valid && !process.ane_group);
 puts("PASS: recognized and rejected ANE layouts, Mach time units, zero, overflow, live GPU scan ownership and platform fallback");
}
