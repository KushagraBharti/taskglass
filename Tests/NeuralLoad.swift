// Bounded real inference fixture, not linked into Taskglass.
import Foundation
import CoreML
import SystemProbe

func groupTime() -> (UInt64, UInt64)? {
    var row = TGProcess(); row.pid = getpid()
    tg_ane_process_groups(&row, 1)
    return row.ane_valid != 0 ? (row.ane_group, row.ane_nanoseconds) : nil
}
let compiled = try MLModel.compileModel(at: URL(fileURLWithPath: ".build/checks/neural-fixture.mlmodel"))
defer { try? FileManager.default.removeItem(at: compiled) }
let configuration = MLModelConfiguration()
configuration.computeUnits = .cpuAndNeuralEngine
let model = try MLModel(contentsOf: compiled, configuration: configuration)
let array = try MLMultiArray(shape: [32, 64, 64], dataType: .float32)
for i in 0..<array.count { array[i] = NSNumber(value: Float(i % 97) / 97) }
let input = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: array)])
let before = groupTime()
try "ready".write(toFile: ".build/checks/neural-load-ready", atomically: true, encoding: .utf8)
let deadline = ProcessInfo.processInfo.systemUptime + 6
var inferences = 0
while ProcessInfo.processInfo.systemUptime < deadline {
    try autoreleasepool { _ = try model.prediction(from: input) }
    inferences += 1
}
let after = groupTime()
if tg_ane_accounting_supported() != 0 {
    guard let before, let after, before.0 == after.0, after.1 > before.1 else {
        fatalError("Inference completed but ANE time did not rise; do not claim successful ANE attribution")
    }
    print("PASS: \(inferences) real inferences, PID \(getpid()), resource group \(after.0), ANE time +\(Double(after.1 - before.1) / 1e6) ms")
} else {
    print("SKIP: ANE time ABI unavailable; \(inferences) CPU/ANE inferences completed without requiring the private counter")
}
