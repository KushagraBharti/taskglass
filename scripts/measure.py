#!/usr/bin/env python3
"""Measure CPU, physical footprint and RSS using libproc. No dependencies."""
import argparse
import ctypes
import json
import statistics
import time

class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [(name, ctypes.c_uint64) for name in (
        "user", "system", "package_wakeups", "interrupt_wakeups", "pageins", "wired", "resident", "footprint", "start", "exit",
        "child_user", "child_system", "child_package", "child_interrupt", "child_pageins", "child_elapsed", "read", "write")]

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=int, default=30)
args = parser.parse_args()
lib = ctypes.CDLL("/usr/lib/libproc.dylib")
lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]

def read():
    value = Usage()
    if lib.proc_pid_rusage(args.pid, 2, ctypes.byref(value)) != 0:
        raise RuntimeError("Process exited or macOS denied access")
    return value

start = time.monotonic()
first = read()
samples = [first]
for _ in range(args.seconds):
    time.sleep(1)
    samples.append(read())
wall = time.monotonic() - start
last = samples[-1]
print(json.dumps({"duration_seconds": round(wall, 2),
    "cpu_percent_one_core": round(((last.user + last.system) - (first.user + first.system))/1e9/wall*100, 3),
    "footprint_mib_median": round(statistics.median(s.footprint for s in samples)/2**20, 2),
    "footprint_mib_peak": round(max(s.footprint for s in samples)/2**20, 2),
    "rss_mib_median": round(statistics.median(s.resident for s in samples)/2**20, 2),
    "interrupt_wakeups_per_second": round((last.interrupt_wakeups-first.interrupt_wakeups)/wall, 2)}, indent=2))
