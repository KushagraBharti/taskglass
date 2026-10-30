#pragma once
#include <stdint.h>
#include <stddef.h>
typedef struct {
 int32_t pid, parent; uint32_t uid; uint64_t birth, cpu, resident, footprint, disk_read, disk_write;
 uint32_t threads; int footprint_valid; char name[256];
} TGProcess;
typedef struct {
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
