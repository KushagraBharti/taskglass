#include "SystemProbe.h"
#include <stdio.h>
#include <unistd.h>
#include <assert.h>
#include <math.h>
int main(void) {
 TGHardwareProbe *p=tg_hardware_create();assert(p);
 TGHardware a=tg_hardware_read(p,1);
 usleep(300000);
 TGHardware b=tg_hardware_read(p,0);
 assert(!b.gpu_valid||(isfinite(b.gpu_usage)&&b.gpu_usage>=0&&b.gpu_usage<=100));
 for(int i=0;i<b.temperature_count;i++)assert(isfinite(b.temperatures[i].value)&&b.temperatures[i].value>=0&&b.temperatures[i].value<=125);
 assert(!(b.power_valid&1)||(isfinite(b.cpu_watts)&&b.cpu_watts>=0));
 assert(!(b.power_valid&2)||(isfinite(b.gpu_watts)&&b.gpu_watts>=0));
 assert(!(b.power_valid&4)||(isfinite(b.ane_watts)&&b.ane_watts>=0));
 assert(!b.storage_valid||b.disk_available<=b.disk_total);
 printf("GPU: %s, %d cores, usage %.1f%%, renderer %.1f%%, tiler %.1f%%\n",b.chip,b.gpu_cores,b.gpu_usage,b.renderer_usage,b.tiler_usage);
 printf("Power valid bits: %d; CPU %.4f W, GPU %.4f W, ANE %.4f W (%s)\n",b.power_valid,b.cpu_watts,b.gpu_watts,b.ane_watts,b.power_source);
 printf("Battery %.0f%%, cycles %d, %.2f W, %.1f C, full/design ratio %.1f%%\n",b.battery_percent,b.battery_cycles,b.battery_watts,b.battery_temperature,b.battery_health);
 printf("Temperature CPU %.1f C, GPU %.1f C, %d named sensors; fans %.0f / %.0f RPM\n",b.cpu_temperature,b.gpu_temperature,b.temperature_count,b.fan0_rpm,b.fan1_rpm);
 printf("Storage valid %d; disk counter delta read %llu / write %llu; tier %s=%d, %s=%d\n",b.storage_valid,b.disk_read-a.disk_read,b.disk_write-a.disk_write,b.tier0_name,b.tier0_cores,b.tier1_name,b.tier1_cores);
 tg_hardware_reset(p);TGHardware reset=tg_hardware_read(p,0);assert(reset.power_valid==0);
 TGHardware summary=tg_hardware_read(p,TG_HARDWARE_SUMMARY);
 assert(summary.temperature_count<=b.temperature_count);
 assert(!isfinite(b.cpu_temperature)||isfinite(summary.cpu_temperature));
 assert(!isfinite(b.gpu_temperature)||isfinite(summary.gpu_temperature));
 TGHardware details=tg_hardware_read(p,TG_HARDWARE_FULL);
 assert(details.temperature_count>=summary.temperature_count);
 printf("Summary %d / full %d readable sensors; group temperatures retained\n",summary.temperature_count,details.temperature_count);
 tg_hardware_destroy(p);
}
