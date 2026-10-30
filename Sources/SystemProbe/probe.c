#include "SystemProbe.h"
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <pthread.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
// Reuse a single host send right for the lifetime of the process.
static host_t tg_host_port;
static pthread_once_t tg_host_once = PTHREAD_ONCE_INIT;
static void tg_init_host(void) { tg_host_port = mach_host_self(); }
TGSystem tg_system(void) {
 pthread_once(&tg_host_once, tg_init_host);
 TGSystem s = {0}; size_t size=sizeof(s.total);
 sysctlbyname("hw.memsize", &s.total, &size, NULL, 0);
 vm_statistics64_data_t v={0}; mach_msg_type_number_t n=HOST_VM_INFO64_COUNT;
 if (host_statistics64(tg_host_port,HOST_VM_INFO64,(host_info64_t)&v,&n)==KERN_SUCCESS) {
  uint64_t p=(uint64_t)getpagesize();
  s.wired=(uint64_t)v.wire_count*p; s.compressed=(uint64_t)v.compressor_page_count*p;
  uint64_t app=v.internal_page_count>v.purgeable_count?v.internal_page_count-v.purgeable_count:0;
  s.used=app*p+s.wired+s.compressed;
  s.cached=((uint64_t)v.external_page_count+v.purgeable_count)*p; s.valid=1;
 }
 host_cpu_load_info_data_t c={0}; n=HOST_CPU_LOAD_INFO_COUNT;
 if(host_statistics(tg_host_port,HOST_CPU_LOAD_INFO,(host_info_t)&c,&n)==KERN_SUCCESS) {
  s.cpu_valid=1;
  s.cpu_user=(uint64_t)c.cpu_ticks[CPU_STATE_USER]+c.cpu_ticks[CPU_STATE_NICE];
  s.cpu_system=c.cpu_ticks[CPU_STATE_SYSTEM]; s.cpu_idle=c.cpu_ticks[CPU_STATE_IDLE];
 }
 processor_info_array_t ticks=NULL; mach_msg_type_number_t tick_count=0; natural_t cores=0;
 if(host_processor_info(tg_host_port,PROCESSOR_CPU_LOAD_INFO,&cores,&ticks,&tick_count)==KERN_SUCCESS) {
  s.cores=cores>128?128:cores;
  for(int i=0;i<s.cores;i++) {
   uint64_t user=(uint32_t)ticks[i*CPU_STATE_MAX+CPU_STATE_USER], nice=(uint32_t)ticks[i*CPU_STATE_MAX+CPU_STATE_NICE];
   uint64_t system=(uint32_t)ticks[i*CPU_STATE_MAX+CPU_STATE_SYSTEM], idle=(uint32_t)ticks[i*CPU_STATE_MAX+CPU_STATE_IDLE];
   s.core_busy[i]=user+nice+system;s.core_total[i]=s.core_busy[i]+idle;
  }
  vm_deallocate(mach_task_self(),(vm_address_t)ticks,tick_count*sizeof(integer_t));
 }
 struct xsw_usage swap={0}; size=sizeof(swap);
 if(sysctlbyname("vm.swapusage",&swap,&size,NULL,0)==0) s.swap=swap.xsu_used;
 size=sizeof(s.pressure); sysctlbyname("kern.memorystatus_vm_pressure_level",&s.pressure,&size,NULL,0);
 // 64-bit interface counters avoid the 4 GB wrap of getifaddrs if_data.
 int mib[6]={CTL_NET,PF_ROUTE,0,0,NET_RT_IFLIST2,0}; size_t length=0;
 if(sysctl(mib,6,NULL,&length,NULL,0)==0 && length>0) {
  char *buffer=malloc(length);
  if(buffer && sysctl(mib,6,buffer,&length,NULL,0)==0) {
   s.net_valid=1;
   char *end=buffer+length;
   for(char *cursor=buffer;cursor+sizeof(struct if_msghdr)<=end;) {
    struct if_msghdr *header=(struct if_msghdr *)cursor;
    if(!header->ifm_msglen || cursor+header->ifm_msglen>end) break;
    if(header->ifm_type==RTM_IFINFO2 && header->ifm_msglen>=sizeof(struct if_msghdr2)+sizeof(struct sockaddr_dl)) {
     struct if_msghdr2 *m=(struct if_msghdr2 *)cursor;
     struct sockaddr_dl *address=(struct sockaddr_dl *)(m+1);
     if(address->sdl_nlen>=2 && address->sdl_data[0]=='e' && address->sdl_data[1]=='n' && (m->ifm_flags&IFF_UP)) {
      s.net_identity ^= (uint64_t)m->ifm_index*2654435761ULL;
      s.received+=m->ifm_data.ifi_ibytes; s.sent+=m->ifm_data.ifi_obytes;
     }
    }
    cursor+=header->ifm_msglen;
   }
  } free(buffer);
 }
 return s;
}
int tg_processes(TGProcess **output) {
 int bytes=proc_listpids(PROC_ALL_PIDS,0,NULL,0);
 if(bytes<=0) { *output=NULL; return 0; }
 int capacity=bytes+4096; pid_t *pids=malloc(capacity);
 if(!pids) { *output=NULL; return 0; }
 int count=proc_listpids(PROC_ALL_PIDS,0,pids,capacity)/(int)sizeof(pid_t);
 if(count<=0) {free(pids);*output=NULL;return 0;}
 TGProcess *rows=calloc(count,sizeof(TGProcess)); int used=0;
 if(!rows) {free(pids);*output=NULL;return 0;}
 for(int i=0;i<count;i++) {
  if(pids[i]<=0) continue;
  struct proc_taskallinfo info={0};
  if(proc_pidinfo(pids[i],PROC_PIDTASKALLINFO,0,&info,sizeof(info))!=sizeof(info)) continue;
  TGProcess *r=&rows[used++]; r->pid=pids[i];r->parent=info.pbsd.pbi_ppid;r->uid=info.pbsd.pbi_uid;
  r->birth=info.pbsd.pbi_start_tvsec*1000000+info.pbsd.pbi_start_tvusec;
  r->cpu=info.ptinfo.pti_total_user+info.ptinfo.pti_total_system;
  r->resident=info.ptinfo.pti_resident_size; r->threads=info.ptinfo.pti_threadnum;
  strlcpy(r->name,info.pbsd.pbi_name[0]?info.pbsd.pbi_name:info.pbsd.pbi_comm,sizeof(r->name));
  struct rusage_info_v2 usage={0};
  if(proc_pid_rusage(r->pid,RUSAGE_INFO_V2,(rusage_info_t *)&usage)==0) {r->footprint=usage.ri_phys_footprint;r->disk_read=usage.ri_diskio_bytesread;r->disk_write=usage.ri_diskio_byteswritten;r->footprint_valid=1;}
 }
 free(pids); *output=rows; return used;
}
void tg_free(void *p) {free(p);}

int tg_path(int pid, char *buffer, int size) { return proc_pidpath(pid,buffer,size); }

int tg_matches(int pid, uint64_t birth) {
 if(pid<=1 || pid==getpid()) return 0;
 struct proc_bsdinfo b={0};
 if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&b,sizeof(b))!=sizeof(b)) return 0;
 if(b.pbi_uid!=getuid() || b.pbi_start_tvsec*1000000+b.pbi_start_tvusec!=birth) return 0;
 return 1;
}
int tg_terminate(int pid, uint64_t birth, int force) {
 if(!tg_matches(pid,birth)) return 0;
 return kill(pid,force?SIGKILL:SIGTERM)==0;
}
