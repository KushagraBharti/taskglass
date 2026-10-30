// IOKit GPU, storage and battery readers. IOReport remains optional at runtime.
// The CLPC channel construction and M5 Pro IDs are adapted from macmon (MIT).
// See THIRD_PARTY_NOTICES.md for provenance and license.
#include "SystemProbe.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#include <time.h>
#include <dlfcn.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

typedef CFTypeRef (*Subscribe)(void *,CFMutableDictionaryRef,CFMutableDictionaryRef *,uint64_t,CFTypeRef);
typedef CFDictionaryRef (*Samples)(CFTypeRef,CFMutableDictionaryRef,CFTypeRef);
typedef CFStringRef (*ChannelString)(CFDictionaryRef);
typedef int64_t (*IntegerValue)(CFDictionaryRef,int);
typedef struct { uint8_t major,minor,build,reserved;uint16_t release; } SMCVersion;
typedef struct { uint16_t version,length;uint32_t cpu,gpu,memory; } SMCLimit;
typedef struct { uint32_t size,type;uint8_t attributes; } SMCInfo;
typedef struct { uint32_t key;SMCVersion version;SMCLimit limit;SMCInfo info;uint8_t result,status,command;uint32_t index;uint8_t bytes[32]; } SMCData;
_Static_assert(sizeof(SMCData)==80,"SMC wire layout");
typedef struct { uint32_t key;SMCInfo info;int kind;char name[5]; } SMCSensor;
typedef struct { char name[48];int kind; } HIDSensor;
struct TGHardwareProbe {
 io_service_t gpu, battery, battery_pack;
 io_connect_t smc;SMCSensor smc_sensors[128];int smc_count;
 TGHardware cached;
 void *library;
 CFTypeRef subscription;
 CFMutableDictionaryRef channels;
 Samples samples; IntegerValue integer; ChannelString name;
 int64_t energy[3]; int energy_seen[3];
 double energy_time;
 CFTypeRef hid_client; CFArrayRef hid_services;
 HIDSensor *hid_metadata;CFIndex hid_count;int hid_initialized;
 CFTypeRef (*hid_event)(CFTypeRef,int64_t,int32_t,int64_t);
 double (*hid_float)(CFTypeRef,int64_t);
 CFTypeRef (*hid_property)(CFTypeRef,CFStringRef);
};
static double seconds(void) {
 struct timespec t; clock_gettime(CLOCK_MONOTONIC_RAW,&t);
 return t.tv_sec+t.tv_nsec/1e9;
}
static CFTypeRef value(CFDictionaryRef d,CFStringRef key) { return d?CFDictionaryGetValue(d,key):NULL; }
static double number(CFDictionaryRef d,CFStringRef key) {
 CFTypeRef v=value(d,key); double out=NAN;
 if(v && CFGetTypeID(v)==CFNumberGetTypeID()) CFNumberGetValue(v,kCFNumberDoubleType,&out);
 return out;
}
static int unsigned_number(CFDictionaryRef d,CFStringRef key,uint64_t *out) {
 CFTypeRef v=value(d,key);int64_t integer=0;
 if(!v||CFGetTypeID(v)!=CFNumberGetTypeID()||!CFNumberGetValue(v,kCFNumberSInt64Type,&integer)||integer<0)return 0;
 *out=(uint64_t)integer;return 1;
}
static int count_number(CFDictionaryRef d,CFStringRef key) {
 uint64_t n=0;return unsigned_number(d,key,&n)&&n<=INT_MAX?(int)n:0;
}
static int boolean(CFDictionaryRef d,CFStringRef key) {
 CFTypeRef v=value(d,key);
 return v && CFGetTypeID(v)==CFBooleanGetTypeID() && CFBooleanGetValue(v);
}
static void text(CFStringRef v,char *out,size_t size) {
 if(v && CFGetTypeID(v)==CFStringGetTypeID()) CFStringGetCString(v,out,size,kCFStringEncodingUTF8);
}
static CFDictionaryRef properties(io_service_t service) {
 CFMutableDictionaryRef result=NULL;
 if(service) IORegistryEntryCreateCFProperties(service,&result,kCFAllocatorDefault,0);
 return result;
}
static int integer_sysctl(const char *key) { int v=0; size_t size=sizeof(v); sysctlbyname(key,&v,&size,NULL,0); return v; }
static void string_sysctl(const char *key,char *v,size_t size) { sysctlbyname(key,v,&size,NULL,0); }
static CFNumberRef cfnumber(uint64_t v) { return CFNumberCreate(NULL,kCFNumberSInt64Type,&v); }
static void setnumber(CFMutableDictionaryRef d,CFStringRef key,uint64_t v) { CFNumberRef n=cfnumber(v);CFDictionarySetValue(d,key,n);CFRelease(n); }

static void energy_init(TGHardwareProbe *p) {
 p->library=dlopen("/usr/lib/libIOReport.dylib",RTLD_LAZY|RTLD_LOCAL);
 if(!p->library) return;
 Subscribe subscribe=(Subscribe)dlsym(p->library,"IOReportCreateSubscription");
 p->samples=(Samples)dlsym(p->library,"IOReportCreateSamples");
 p->integer=(IntegerValue)dlsym(p->library,"IOReportSimpleGetIntegerValue");
 p->name=(ChannelString)dlsym(p->library,"IOReportChannelGetChannelName");
 if(!subscribe || !p->samples || !p->integer || !p->name) return;
 io_service_t clpc=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleCLPC"));
 if(!clpc) return;
 CFDictionaryRef props=properties(clpc);
 char bundle[128]={0},version[32]={0};
 text(value(props,CFSTR("CFBundleIdentifier")),bundle,sizeof(bundle));
 string_sysctl("kern.osproductversion",version,sizeof(version));
 uint64_t driver=0; IORegistryEntryGetRegistryEntryID(clpc,&driver);
 IOObjectRelease(clpc); if(props) CFRelease(props);
 uint32_t keys[3]={0};
 // These IDs are OS/driver specific. Never guess a mapping for an unknown driver.
 if(strncmp(version,"27.",3)==0 && strcmp(bundle,"com.apple.driver.AppleT6050CLPC")==0) {
  keys[0]=0xd3ab60bb;keys[1]=0x27cd4ce5;keys[2]=0x8c0f1c59;
 } else if(strncmp(version,"27.",3)==0 && strcmp(bundle,"com.apple.driver.AppleT6050dCLPC")==0) {
  keys[0]=0x18b3010e;keys[1]=0xedeca11a;keys[2]=0x188bd883;
 } else return;
 // These three recognized descriptors are sufficient. Fetching every channel
 // first needlessly allocates the entire system legend and raises cold memory.
 CFMutableDictionaryRef selected=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 CFMutableArrayRef channels=CFArrayCreateMutable(NULL,0,&kCFTypeArrayCallBacks);
 const CFStringRef names[]={CFSTR("CPU Energy"),CFSTR("GPU Energy"),CFSTR("ANE")};
 const uint64_t indices[]={16,25,24};
 for(int i=0;i<3;i++) {
  CFMutableDictionaryRef channel=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
  setnumber(channel,CFSTR("DriverID"),driver);
  CFDictionarySetValue(channel,CFSTR("DriverName"),CFSTR("AppleCLPC"));
  CFDictionarySetValue(channel,CFSTR("IOReportGroupName"),CFSTR("CLPC"));
  CFDictionarySetValue(channel,CFSTR("IOReportSubGroupName"),CFSTR("Energy Counters"));
  CFMutableDictionaryRef info=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
  setnumber(info,CFSTR("IOReportChannelUnit"),(3ULL<<56)|(118ULL<<32));
  CFDictionarySetValue(channel,CFSTR("IOReportChannelInfo"),info);CFRelease(info);
  CFNumberRef id=cfnumber((indices[i]<<32)|keys[i]),type=cfnumber(1ULL|(2ULL<<16)|(1ULL<<32));
  const void *items[]={id,type,names[i]};
  CFArrayRef legend=CFArrayCreate(NULL,items,3,&kCFTypeArrayCallBacks);
  CFDictionarySetValue(channel,CFSTR("LegendChannel"),legend);
  CFRelease(id);CFRelease(type);CFRelease(legend);
  CFArrayAppendValue(channels,channel);CFRelease(channel);
 }
 CFDictionarySetValue(selected,CFSTR("IOReportChannels"),channels);CFRelease(channels);
 p->subscription=subscribe(NULL,selected,&p->channels,0,NULL);CFRelease(selected);
 if(p->subscription && p->channels) strlcpy(p->cached.power_source,"CLPC · experimental",sizeof(p->cached.power_source));
}
static void energy_read(TGHardwareProbe *p,TGHardware *s) {
 s->cpu_watts=s->gpu_watts=s->ane_watts=NAN;s->power_valid=0;
 if(!p->subscription || !p->channels) return;
 CFDictionaryRef sample=p->samples(p->subscription,p->channels,NULL); if(!sample) return;
 CFArrayRef list=value(sample,CFSTR("IOReportChannels"));
 double now=seconds(),elapsed=now-p->energy_time;
 if(list && CFGetTypeID(list)==CFArrayGetTypeID()) for(CFIndex i=0;i<CFArrayGetCount(list);i++) {
  CFDictionaryRef item=CFArrayGetValueAtIndex(list,i);
  char name[64]={0};text(p->name(item),name,sizeof(name));
  int index=strcmp(name,"CPU Energy")==0?0:strcmp(name,"GPU Energy")==0?1:strcmp(name,"ANE")==0?2:-1;
  if(index<0) continue;
  int64_t next=p->integer(item,0);
  if(next>=0 && p->energy_seen[index] && next>=p->energy[index] && elapsed>0) {
   double watts=(next-p->energy[index])/1e9/elapsed;
   if(isfinite(watts) && watts>=0 && watts<500) {
    if(index==0)s->cpu_watts=watts;else if(index==1)s->gpu_watts=watts;else s->ane_watts=watts;
    s->power_valid|=1<<index;
   }
  }
  p->energy[index]=next;p->energy_seen[index]=next>=0;
 }
 p->energy_time=now;CFRelease(sample);
}
static void gpu_read(TGHardwareProbe *p,TGHardware *s) {
 s->gpu_valid=s->gpu_memory_valid=0;s->gpu_usage=s->renderer_usage=s->tiler_usage=NAN;
 if(!p->gpu) return;
 CFTypeRef stats=IORegistryEntryCreateCFProperty(p->gpu,CFSTR("PerformanceStatistics"),NULL,0);
 if(!stats || CFGetTypeID(stats)!=CFDictionaryGetTypeID()) {if(stats)CFRelease(stats);return;}
 s->gpu_usage=number(stats,CFSTR("Device Utilization %"));s->renderer_usage=number(stats,CFSTR("Renderer Utilization %"));s->tiler_usage=number(stats,CFSTR("Tiler Utilization %"));
 s->gpu_valid=isfinite(s->gpu_usage)&&s->gpu_usage>=0&&s->gpu_usage<=100;
 if(!isfinite(s->renderer_usage)||s->renderer_usage<0||s->renderer_usage>100)s->renderer_usage=NAN;
 if(!isfinite(s->tiler_usage)||s->tiler_usage<0||s->tiler_usage>100)s->tiler_usage=NAN;
 s->gpu_memory_valid=unsigned_number(stats,CFSTR("Alloc system memory"),&s->gpu_allocated)&&unsigned_number(stats,CFSTR("In use system memory"),&s->gpu_in_use);
 CFRelease(stats);
}
static uint32_t smc_key(const char *s){return (uint32_t)(uint8_t)s[0]<<24|(uint32_t)(uint8_t)s[1]<<16|(uint32_t)(uint8_t)s[2]<<8|(uint8_t)s[3];}
static int smc_call(TGHardwareProbe *p,SMCData *in,SMCData *out) {
 size_t size=sizeof(*out);
 return IOConnectCallStructMethod(p->smc,2,in,sizeof(*in),out,&size)==KERN_SUCCESS && size==sizeof(*out) && out->result==0;
}
static int smc_info(TGHardwareProbe *p,uint32_t key,SMCInfo *info) {
 SMCData in={0},out={0};in.key=key;in.command=9;
 if(!smc_call(p,&in,&out)||out.info.size>32)return 0;*info=out.info;return 1;
}
static double smc_value(TGHardwareProbe *p,SMCSensor sensor) {
 SMCData in={0},out={0};in.key=sensor.key;in.info=sensor.info;in.command=5;
 if(!smc_call(p,&in,&out))return NAN;
 if(sensor.info.type==smc_key("flt ") && sensor.info.size==4) {float value;memcpy(&value,out.bytes,4);return value;}
 if(sensor.info.type==smc_key("sp78") && sensor.info.size==2)return (int16_t)((out.bytes[0]<<8)|out.bytes[1])/256.0;
 if(sensor.info.type==smc_key("fpe2") && sensor.info.size==2)return ((out.bytes[0]<<8)|out.bytes[1])/4.0;
 return NAN;
}
static void smc_init(TGHardwareProbe *p) {
 io_iterator_t iterator=0;
 if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("AppleSMC"),&iterator)!=KERN_SUCCESS)return;
 io_service_t service;
 while((service=IOIteratorNext(iterator))) {
  io_name_t name={0};IORegistryEntryGetName(service,name);
  if(strcmp(name,"AppleSMCKeysEndpoint")==0)IOServiceOpen(service,mach_task_self(),0,&p->smc);
  IOObjectRelease(service);
 }IOObjectRelease(iterator);if(!p->smc)return;
 uint32_t key=smc_key("#KEY");SMCInfo info;
 if(!smc_info(p,key,&info))return;
 SMCData in={0},out={0};in.key=key;in.info=info;in.command=5;
 if(!smc_call(p,&in,&out))return;
 uint32_t count=(uint32_t)out.bytes[0]<<24|(uint32_t)out.bytes[1]<<16|(uint32_t)out.bytes[2]<<8|out.bytes[3];
 if(count>16384)return;
 for(uint32_t i=0;i<count&&p->smc_count<128;i++) {
  in=(SMCData){0};out=(SMCData){0};in.command=8;in.index=i;
  if(!smc_call(p,&in,&out))continue;
  char name[5]={(out.key>>24)&255,(out.key>>16)&255,(out.key>>8)&255,out.key&255,0};
  int kind=name[0]=='F'&&name[2]=='A'&&name[3]=='c'?6:name[0]=='F'&&name[2]=='M'&&name[3]=='x'?7:name[0]=='T'&&name[1]=='g'?2:name[0]=='T'&&(name[1]=='p'||name[1]=='e'||name[1]=='s')?1:0;
  if(!kind)continue;
  SMCSensor sensor={0};sensor.key=out.key;sensor.kind=kind;strlcpy(sensor.name,name,5);
  if(smc_info(p,sensor.key,&sensor.info) && isfinite(smc_value(p,sensor)))p->smc_sensors[p->smc_count++]=sensor;
 }
}
static void append_temperature(TGHardware *h,const char *name,const char *source,int kind,uint64_t id,double value) {
 if(h->temperature_count>=192||!isfinite(value)||value<0||value>125)return;
 TGTemperature *sensor=&h->temperatures[h->temperature_count++];
 strlcpy(sensor->name,name,sizeof(sensor->name));strlcpy(sensor->source,source,sizeof(sensor->source));
 sensor->value=value;sensor->kind=kind;sensor->identifier=id;
}
static void smc_read(TGHardwareProbe *p) {
 double cpu=0,gpu=0;int nc=0,ng=0;
 for(int i=0;i<p->smc_count;i++) {
  SMCSensor sensor=p->smc_sensors[i];double v=smc_value(p,sensor);
  if(!isfinite(v))continue;
  if(sensor.kind==7) {
   if(v>0&&v<20000){if(sensor.name[1]=='0')p->cached.fan0_max=v;if(sensor.name[1]=='1')p->cached.fan1_max=v;}
   continue;
  }
  if(sensor.kind==6) {
   if(v>=0&&v<20000){if(sensor.name[1]=='0')p->cached.fan0_rpm=v;if(sensor.name[1]=='1')p->cached.fan1_rpm=v;}
   continue;
  }
  if(v<=0||v>125)continue;
  append_temperature(&p->cached,sensor.name,"SMC",sensor.kind,sensor.key,v);
  if(sensor.kind==1){cpu+=v;nc++;}else if(sensor.kind==2){gpu+=v;ng++;}
 }
 if(nc)p->cached.cpu_temperature=cpu/nc;if(ng)p->cached.gpu_temperature=gpu/ng;
}
static void sensors_init(TGHardwareProbe *p) {
 p->hid_initialized=1;
 CFTypeRef (*create)(CFAllocatorRef)=dlsym(RTLD_DEFAULT,"IOHIDEventSystemClientCreate");
 int (*matching)(CFTypeRef,CFDictionaryRef)=dlsym(RTLD_DEFAULT,"IOHIDEventSystemClientSetMatching");
 CFArrayRef (*services)(CFTypeRef)=dlsym(RTLD_DEFAULT,"IOHIDEventSystemClientCopyServices");
 p->hid_event=dlsym(RTLD_DEFAULT,"IOHIDServiceClientCopyEvent");
 p->hid_float=dlsym(RTLD_DEFAULT,"IOHIDEventGetFloatValue");
 p->hid_property=dlsym(RTLD_DEFAULT,"IOHIDServiceClientCopyProperty");
 if(!create||!matching||!services||!p->hid_event||!p->hid_float||!p->hid_property)return;
 p->hid_client=create(NULL);if(!p->hid_client)return;
 CFMutableDictionaryRef filter=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
 setnumber(filter,CFSTR("PrimaryUsagePage"),0xff00);setnumber(filter,CFSTR("PrimaryUsage"),5);
 matching(p->hid_client,filter);CFRelease(filter);
 p->hid_services=services(p->hid_client);
 if(!p->hid_services)return;
 p->hid_count=CFArrayGetCount(p->hid_services);
 if(p->hid_count>4096){p->hid_count=0;return;}
 p->hid_metadata=calloc((size_t)p->hid_count,sizeof(HIDSensor));
 if(!p->hid_metadata){p->hid_count=0;return;}
 // Product names and sensor classifications are immutable for these retained
 // service handles. Do not fetch/allocate them again at every temperature read.
 for(CFIndex i=0;i<p->hid_count;i++) {
  CFTypeRef service=CFArrayGetValueAtIndex(p->hid_services,i);
  CFTypeRef product=p->hid_property(service,CFSTR("Product"));
  char name[160]={0};text(product,name,sizeof(name));if(product)CFRelease(product);
  HIDSensor *sensor=&p->hid_metadata[i];strlcpy(sensor->name,name,sizeof(sensor->name));
  int cpu=strstr(name,"CPU MTR")||strstr(name,"pACC")||strstr(name,"eACC");
  sensor->kind=cpu?1:strstr(name,"GPU MTR")?2:strstr(name,"NAND")?4:strstr(name,"battery")?5:3;
 }
}
static void sensors_read(TGHardwareProbe *p) {
 double cpu=0,gpu=0;int nc=0,ng=0;
 if(!p->hid_services||!p->hid_metadata)return;
 for(CFIndex i=0;i<p->hid_count;i++) {
  CFTypeRef service=CFArrayGetValueAtIndex(p->hid_services,i);
  const HIDSensor *sensor=&p->hid_metadata[i];
  CFTypeRef event=p->hid_event(service,15,0,0);if(!event)continue;
  double temp=p->hid_float(event,15<<16);CFRelease(event);
  if(isfinite(temp)&&temp>0&&temp<125){
   append_temperature(&p->cached,sensor->name,"IOHID",sensor->kind,(uint64_t)i+1,temp);
   if(sensor->kind==1){cpu+=temp;nc++;}if(sensor->kind==2){gpu+=temp;ng++;}
  }
 }
 p->cached.cpu_temperature=nc?cpu/nc:NAN;p->cached.gpu_temperature=ng?gpu/ng:NAN;
}
static void core_topology(TGHardwareProbe *p) {
 io_registry_entry_t node=IORegistryEntryFromPath(kIOMainPortDefault,"IODeviceTree:/cpus");
 if(!node)return;
 io_iterator_t iterator=0;
 if(IORegistryEntryGetChildIterator(node,kIODeviceTreePlane,&iterator)==KERN_SUCCESS) {
  io_registry_entry_t cpu;
  while((cpu=IOIteratorNext(iterator))) {
   CFDictionaryRef props=properties(cpu);
   if(props) {
    double logical=number(props,CFSTR("logical-cpu-id"));
    CFTypeRef kind=value(props,CFSTR("cluster-type"));
    if(isfinite(logical)&&logical>=0&&logical<128&&kind&&CFGetTypeID(kind)==CFDataGetTypeID()&&CFDataGetLength(kind)>0)
     p->cached.core_kind[(int)logical]=CFDataGetBytePtr(kind)[0];
    CFRelease(props);
   }IOObjectRelease(cpu);
  }IOObjectRelease(iterator);
 }IOObjectRelease(node);
}
static void slow_read(TGHardwareProbe *p,int details) {
 TGHardware *s=&p->cached;
 s->temperature_count=0;s->cpu_temperature=s->gpu_temperature=s->fan0_rpm=s->fan1_rpm=NAN;
 s->battery_percent=s->battery_temperature=s->battery_health=s->battery_voltage=s->battery_minutes=s->battery_watts=NAN;
 smc_read(p);
 // CPU/GPU group averages and fans remain live on every pane. The additional
 // raw IOHID table is only requested when visible, or as a fallback if SMC does
 // not provide a usable group. Preserve SMC priority when both sources exist.
 if(details||!isfinite(s->cpu_temperature)||!isfinite(s->gpu_temperature)) {
  double smc_cpu=s->cpu_temperature,smc_gpu=s->gpu_temperature;
  if(!p->hid_initialized)sensors_init(p);
  sensors_read(p);
  if(isfinite(smc_cpu))s->cpu_temperature=smc_cpu;
  if(isfinite(smc_gpu))s->gpu_temperature=smc_gpu;
 }
 s->storage_valid=0;
 struct statfs fs;
 if(statfs("/System/Volumes/Data",&fs)==0 || statfs("/",&fs)==0) {
  s->disk_total=(uint64_t)fs.f_blocks*fs.f_bsize;s->disk_available=(uint64_t)fs.f_bavail*fs.f_bsize;s->storage_valid=1;
 }
 CFDictionaryRef b=properties(p->battery);
 if(b) {
  s->battery_present=1;
  s->battery_percent=number(b,CFSTR("CurrentCapacity"));
  if(!isfinite(s->battery_percent)||s->battery_percent<0||s->battery_percent>100)s->battery_percent=NAN;
  s->battery_cycles=count_number(b,CFSTR("CycleCount"));
  s->battery_charging=boolean(b,CFSTR("IsCharging"));s->battery_external=boolean(b,CFSTR("ExternalConnected"));
  double temp=number(b,CFSTR("Temperature"));s->battery_temperature=isfinite(temp)?temp/100:NAN;
  // Signed two's-complement current is represented as a CFNumber, not an unsigned watt value.
  CFTypeRef current=value(b,CFSTR("Amperage"));int64_t ma=0;
  double voltage=number(b,CFSTR("Voltage"));s->battery_voltage=voltage/1000;
  if(current && CFGetTypeID(current)==CFNumberGetTypeID() && CFNumberGetValue(current,kCFNumberSInt64Type,&ma) && isfinite(voltage)) s->battery_watts=(double)ma*voltage/1e6;
  double maximum=number(b,CFSTR("AppleRawMaxCapacity")),design=number(b,CFSTR("DesignCapacity"));
  s->battery_health=isfinite(maximum)&&maximum>=0&&design>0?maximum/design*100:NAN;
  CFDictionaryRef data=value(b,CFSTR("BatteryData"));
  if(data && CFGetTypeID(data)==CFDictionaryGetTypeID()) {
   double full=number(data,CFSTR("FullChargeCapacity")),capacity=number(data,CFSTR("DesignCapacity"));
   double minutes=number(data,CFSTR("AvgTimeToEmpty"));s->battery_minutes=!s->battery_charging&&!s->battery_external&&minutes>0&&minutes<65535?minutes:NAN;
   if(isfinite(full)&&full>=0&&capacity>0)s->battery_health=full/capacity*100;
  }
  CFRelease(b);
 }
 CFDictionaryRef pack=properties(p->battery_pack);
 if(pack) {
  CFDictionaryRef data=value(pack,CFSTR("BatteryData"));
  if(data && CFGetTypeID(data)==CFDictionaryGetTypeID()) {
   double temp=number(data,CFSTR("Temperature"));
   if(isfinite(temp)&&temp>0&&temp<10000)s->battery_temperature=temp/100;
  }
  CFRelease(pack);
 }
}
TGHardwareProbe *tg_hardware_create(void) {
 TGHardwareProbe *p=calloc(1,sizeof(*p));if(!p)return NULL;
 p->cached.cpu_temperature=p->cached.gpu_temperature=p->cached.fan0_rpm=p->cached.fan1_rpm=p->cached.fan0_max=p->cached.fan1_max=NAN;
 p->cached.battery_percent=p->cached.battery_temperature=p->cached.battery_watts=p->cached.battery_health=p->cached.battery_voltage=p->cached.battery_minutes=NAN;
 p->gpu=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AGXAccelerator"));
 p->battery=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSmartBattery"));
 p->battery_pack=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSmartBatteryPack"));
 CFDictionaryRef gpu=properties(p->gpu);
 if(gpu) {p->cached.gpu_cores=count_number(gpu,CFSTR("gpu-core-count"));text(value(gpu,CFSTR("model")),p->cached.chip,sizeof(p->cached.chip));CFRelease(gpu);}
 if(!p->cached.chip[0])string_sysctl("machdep.cpu.brand_string",p->cached.chip,sizeof(p->cached.chip));
 string_sysctl("hw.model",p->cached.model,sizeof(p->cached.model));
 p->cached.tier0_cores=integer_sysctl("hw.perflevel0.logicalcpu");
 p->cached.tier1_cores=integer_sysctl("hw.perflevel1.logicalcpu");
 string_sysctl("hw.perflevel0.name",p->cached.tier0_name,sizeof(p->cached.tier0_name));
 string_sysctl("hw.perflevel1.name",p->cached.tier1_name,sizeof(p->cached.tier1_name));
 io_service_t ane=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceNameMatching("ane0"));
 if(ane){p->cached.ane_present=1;IOObjectRelease(ane);}
 // The first requested slow sample populates live metadata. Avoid reading all
 // sensors twice during the first HardwareReader.read call.
 core_topology(p);smc_init(p);energy_init(p);return p;
}
TGHardware tg_hardware_read(TGHardwareProbe *p,int mode) {
 TGHardware empty={0};if(!p)return empty;
 if(mode!=TG_HARDWARE_FAST)slow_read(p,mode==TG_HARDWARE_FULL);
 TGHardware s=p->cached;gpu_read(p,&s);energy_read(p,&s);
 int ops_valid=1;
 io_iterator_t iterator=0;
 if(IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOBlockStorageDriver"),&iterator)==KERN_SUCCESS) {
  io_service_t disk;
  while((disk=IOIteratorNext(iterator))) {
   uint64_t id=0;IORegistryEntryGetRegistryEntryID(disk,&id);s.disk_identity^=id;
   CFTypeRef stats=IORegistryEntryCreateCFProperty(disk,CFSTR("Statistics"),NULL,0);
   if(stats&&CFGetTypeID(stats)==CFDictionaryGetTypeID()) {
    uint64_t read=0,write=0,ro=0,wo=0;
    if(unsigned_number(stats,CFSTR("Bytes (Read)"),&read)&&unsigned_number(stats,CFSTR("Bytes (Write)"),&write)){
     s.disk_read+=read;s.disk_write+=write;s.disk_valid=1;
     if(unsigned_number(stats,CFSTR("Operations (Read)"),&ro)&&unsigned_number(stats,CFSTR("Operations (Write)"),&wo)) {
      s.disk_read_ops+=ro;s.disk_write_ops+=wo;
     } else ops_valid=0;
    }
   }
   if(stats)CFRelease(stats);IOObjectRelease(disk);
  }IOObjectRelease(iterator);
 }
 s.disk_ops_valid=s.disk_valid&&ops_valid;
 return s;
}
void tg_hardware_reset(TGHardwareProbe *p){if(p){memset(p->energy_seen,0,sizeof(p->energy_seen));p->energy_time=0;}}
void tg_hardware_destroy(TGHardwareProbe *p) {
 if(!p)return;
 if(p->smc)IOServiceClose(p->smc);
 if(p->gpu)IOObjectRelease(p->gpu);if(p->battery)IOObjectRelease(p->battery);if(p->battery_pack)IOObjectRelease(p->battery_pack);
 if(p->subscription)CFRelease(p->subscription);if(p->channels)CFRelease(p->channels);
 free(p->hid_metadata);if(p->hid_services)CFRelease(p->hid_services);if(p->hid_client)CFRelease(p->hid_client);
 if(p->library)dlclose(p->library);free(p);
}
