#!/usr/bin/env python3
"""Measure CPU, physical footprint and RSS using libproc. No dependencies."""
import argparse
import ctypes
import json
import re
from pathlib import Path
import statistics
import time

class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_ubyte * 16)] + [(name, ctypes.c_uint64) for name in (
        "user", "system", "package_wakeups", "interrupt_wakeups", "pageins", "wired", "resident", "footprint", "start", "exit",
        "child_user", "child_system", "child_package", "child_interrupt", "child_pageins", "child_elapsed", "read", "write")]

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=int, default=30)
parser.add_argument("--events", type=Path, help="stderr file from --profile-events, for exposure attribution")
parser.add_argument("--label", default="unspecified")
args = parser.parse_args()
if args.seconds < 1:
    parser.error("--seconds must be positive")
lib = ctypes.CDLL("/usr/lib/libproc.dylib")
lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]

def read():
    value = Usage()
    if lib.proc_pid_rusage(args.pid, 2, ctypes.byref(value)) != 0:
        raise RuntimeError("Process exited or macOS denied access")
    return value

class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]

clock = Timebase()
if ctypes.CDLL(None).mach_timebase_info(ctypes.byref(clock)) != 0 or clock.denom == 0:
    raise RuntimeError("Mach clock conversion unavailable")
ns_per_tick = clock.numer / clock.denom

# Match Foundation systemUptime for event attribution. Python monotonic may
# use a process-relative epoch on macOS, so its absolute value is unsuitable.
def uptime():
    return time.clock_gettime(time.CLOCK_UPTIME_RAW)

start = uptime()
first = read()
samples = [first]
timestamps = [start]
for _ in range(args.seconds):
    time.sleep(1)
    samples.append(read())
    timestamps.append(uptime())
wall = uptime() - start
last = samples[-1]
report = {"label": args.label, "duration_seconds": round(wall, 2),
    "cpu_timebase_numer": clock.numer,
    "cpu_timebase_denom": clock.denom,
    "cpu_percent_one_core": round(((last.user + last.system) - (first.user + first.system))*ns_per_tick/1e9/wall*100, 3),
    "footprint_mib_median": round(statistics.median(s.footprint for s in samples)/2**20, 2),
    "footprint_mib_peak": round(max(s.footprint for s in samples)/2**20, 2),
    "footprint_mib_first": round(first.footprint/2**20, 2),
    "footprint_mib_last": round(last.footprint/2**20, 2),
    "rss_mib_median": round(statistics.median(s.resident for s in samples)/2**20, 2),
    "interrupt_wakeups_per_second": round((last.interrupt_wakeups-first.interrupt_wakeups)/wall, 2)}


if args.events:
    pattern = re.compile(r"TG_PROFILE t=([0-9.]+) event=(\w+) exposed=([01]) pane=(\w+)")
    events = [(float(t), kind, int(exposed), pane) for t, kind, exposed, pane
              in pattern.findall(args.events.read_text())]
    events.sort()
    exposure_seconds = {"exposed": 0.0, "covered": 0.0, "unknown": 0.0}
    state = None
    for t, kind, exposed, pane in events:
        if t <= start:
            state = exposed
    cursor = start
    for t, kind, exposed, pane in events:
        if start < t < timestamps[-1]:
            exposure_seconds["unknown" if state is None else "exposed" if state else "covered"] += t-cursor
            cursor = t
            state = exposed
    exposure_seconds["unknown" if state is None else "exposed" if state else "covered"] += timestamps[-1]-cursor
    report["window_seconds"] = {k: round(v, 2) for k, v in exposure_seconds.items()}
    report["sample_events"] = sum(start <= t <= timestamps[-1] and kind == "sample"
                                  for t, kind, exposed, pane in events)
    report["observed_panes"] = sorted({pane for t, kind, exposed, pane in events
                                       if start <= t <= timestamps[-1]})
    report["method_note"] = "Release app with opt-in event diagnostics; window exposure is recorded, external workload is uncontrolled."
print(json.dumps(report, indent=2))
