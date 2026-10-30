#include "SystemProbe.h"
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <stdio.h>
#include <unistd.h>

// Standalone native-probe cost, excluding SwiftUI/AppKit and the process list.
int main(void) {
 mach_timebase_info_data_t clock;mach_timebase_info(&clock);
 double ms_per_tick=(double)clock.numer/clock.denom/1e6;
 uint64_t start=mach_absolute_time();
 TGHardwareProbe *probe=tg_hardware_create();if(!probe)return 1;
 TGHardware sample=tg_hardware_read(probe,TG_HARDWARE_SUMMARY);
 double startup=(mach_absolute_time()-start)*ms_per_tick;
 start=mach_absolute_time();
 for(int i=0;i<100;i++)sample=tg_hardware_read(probe,0);
 double fast=(mach_absolute_time()-start)*ms_per_tick/100;
 start=mach_absolute_time();
 for(int i=0;i<10;i++)sample=tg_hardware_read(probe,TG_HARDWARE_SUMMARY);
 double summary=(mach_absolute_time()-start)*ms_per_tick/10;
 start=mach_absolute_time();
 for(int i=0;i<10;i++)sample=tg_hardware_read(probe,TG_HARDWARE_FULL);
 double slow=(mach_absolute_time()-start)*ms_per_tick/10;
 struct rusage_info_v2 usage={0};
 int valid=proc_pid_rusage(getpid(),RUSAGE_INFO_V2,(rusage_info_t*)&usage)==0;
 printf("{\"startup_ms\":%.3f,\"fast_read_ms\":%.3f,\"summary_read_ms\":%.3f,\"full_sensor_read_ms\":%.3f,\"native_probe_footprint_mib\":%.3f,\"readable_sensors\":%d}\n",startup,fast,summary,slow,valid?usage.ri_phys_footprint/1048576.0:-1,sample.temperature_count);
 tg_hardware_destroy(probe);
 return valid?0:1;
}
