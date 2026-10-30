// Short, bounded Metal workload for validating driver counters. Not part of the app.
import Foundation
import Metal
guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { fatalError("Metal unavailable") }
let source = """
#include <metal_stdlib>
using namespace metal;
kernel void sampleLoad(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
    float value = float(id) * 0.00001f;
    for (uint i = 0; i < 1024; ++i) { value = fast::sin(value) * 0.9f + 0.1f; }
    out[id] = value;
}
"""
let library = try device.makeLibrary(source: source, options: nil)
let pipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "sampleLoad")!)
let count = 1 << 20
let buffer = device.makeBuffer(length: count * MemoryLayout<Float>.size, options: .storageModeShared)!
let deadline = ProcessInfo.processInfo.systemUptime + 6
var started = false
while ProcessInfo.processInfo.systemUptime < deadline {
    autoreleasepool {
        let command = queue.makeCommandBuffer()!
        let encoder = command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding(); command.commit()
        if !started { try? "ready".write(toFile: ".build/checks/gpu-load-ready", atomically: true, encoding: .utf8); started = true }
        command.waitUntilCompleted()
        precondition(command.status == .completed)
    }
}
print("PASS: six-second Metal workload completed")
