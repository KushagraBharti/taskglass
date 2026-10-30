#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct {
 int32_t pid, parent; uint32_t uid; uint64_t birth, cpu, resident, footprint, disk_read, disk_write;
 uint32_t threads; int footprint_valid; char name[64];
} TGProcess;
typedef struct { char name[16]; uint64_t received, sent; } TGInterface;
typedef struct {
 int interface_count; TGInterface interfaces[16];
 uint64_t total, used, wired, compressed, cached, swap;
 uint64_t cpu_user, cpu_system, cpu_idle, received, sent;
 int pressure, valid, cores, cpu_valid, net_valid;
 uint64_t net_identity;
 uint64_t core_busy[128], core_total[128];
} TGSystem;
TGSystem tg_system(void);
int tg_processes(TGProcess **output);
void tg_free(void *pointer);

int tg_path(int pid, char *buffer, int size);

int tg_terminate(int pid, uint64_t birth, int force);

int tg_matches(int pid, uint64_t birth);

typedef struct TGHardwareProbe TGHardwareProbe;
typedef struct { char name[48], source[16]; double value; int kind; uint64_t identifier; } TGTemperature;
typedef struct {
 double gpu_usage, renderer_usage, tiler_usage;
 uint64_t gpu_allocated, gpu_in_use, disk_read, disk_write, disk_total, disk_available;
 int gpu_valid, gpu_memory_valid, disk_valid, disk_ops_valid, storage_valid, gpu_cores;
 double cpu_watts, gpu_watts, ane_watts, cpu_temperature, gpu_temperature;
 int power_valid, ane_present, performance_cores, efficiency_cores;
 double battery_percent, battery_temperature, battery_watts, battery_health;
 int battery_present, battery_charging, battery_external, battery_cycles;
 char chip[128], model[64], power_source[64], tier0_name[64], tier1_name[64];
 int tier0_cores, tier1_cores;
 char core_kind[128];
 uint64_t disk_identity, disk_read_ops, disk_write_ops;
 double battery_voltage, battery_minutes;
 int temperature_count; TGTemperature temperatures[192];
 double fan0_rpm, fan1_rpm, fan0_max, fan1_max;
} TGHardware;
TGHardwareProbe *tg_hardware_create(void);
enum { TG_HARDWARE_FAST = 0, TG_HARDWARE_FULL = 1, TG_HARDWARE_SUMMARY = 2 };
TGHardware tg_hardware_read(TGHardwareProbe *probe, int mode);
void tg_hardware_reset(TGHardwareProbe *probe);
void tg_hardware_destroy(TGHardwareProbe *probe);
