import SwiftUI
import AppKit
import SystemProbe

@MainActor final class Monitor: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var history: [Point] = []
    @Published var search = ""
    @Published var interval = 2.0 { didSet { if [1.0, 2, 5].contains(interval) { preferences.save(interval, for: "interval") } } }
    @Published var paused = false
    @Published var selected: Int32? { didSet {
        if oldValue != selected {
            trackedProcess = nil; selectedSamples.removeAll(keepingCapacity: true)
            if windowExposed { processHistory = [] }
        }
    } }
    @Published var scope = 0
    @Published var sort = "memory" { didSet { preferences.save(sort, for: "sort") } }
    @Published var ascending = false { didSet { preferences.save(ascending, for: "ascending") } }
    @Published var rows: [ProcessRow] = []
    @Published var sensorScope = "All" { didSet { preferences.save(sensorScope, for: "sensorScope") } }
    @Published var inspect = false
    @Published var page = 1
    @Published var pane: ResourcePane? = .overview
    @Published var historySeconds = 60.0 { didSet { if [60.0, 180, 600].contains(historySeconds) { preferences.save(historySeconds, for: "historySeconds") } } }
    @Published var overviewProcesses: [ProcessRow] = []
    @Published var resourceSort = "cpu" { didSet {
        if let pane, pane != .overview, pane != .processes, ["cpu", "memory", "gpu", "ane", "neural", "disk", "read", "write"].contains(resourceSort) {
            paneRankings[pane.rawValue] = resourceSort
            preferences.save(paneRankings, for: "paneRankings")
        }
    } }
    @Published var resourceGrouped = true { didSet { preferences.save(resourceGrouped, for: "resourceGrouped") } }
    @Published var resourceLeaders: [ProcessRow] = []
    @Published var resourceSampleDate: Date?
    private var resourceSample: [ProcessRow] = []
    private var overviewTick = 0
    private var windowExposed = true
    private var stagedHistory: [Point]?
    private var stagedSnapshot: Snapshot?
    private var lastProcessSampleDate: Date?
    private var needsBaselineReset = false
    private let preferences: AppPreferences
    private var paneRankings: [String: String] = [:]
    private var trackedProcess: ProcessRow?
    private var selectedSamples: [Point] = []
    @Published var processHistory: [Point] = []

    convenience init() { self.init(preferences: .forApplication()) }
    init(preferences: AppPreferences) {
        self.preferences = preferences
        let interval = preferences.number("interval", fallback: 2)
        self.interval = [1.0, 2, 5].contains(interval) ? interval : 2
        let duration = preferences.number("historySeconds", fallback: 60)
        historySeconds = [60.0, 180, 600].contains(duration) ? duration : 60
        resourceGrouped = preferences.bool("resourceGrouped", fallback: true)
        showResident = preferences.bool("showResident", fallback: false)
        showDisk = preferences.bool("showDisk", fallback: false)
        showUser = preferences.bool("showUser", fallback: false)
        showGPU = preferences.bool("showGPU", fallback: true)
        showNeuralMemory = preferences.bool("showNeuralMemory", fallback: true)
        ascending = preferences.bool("ascending", fallback: false)
        let sort = preferences.string("sort", fallback: "memory")
        self.sort = ["name", "pid", "cpu", "gpu", "neural", "memory", "resident", "threads", "read", "write", "disk", "uid"].contains(sort) ? sort : "memory"
        let sensor = preferences.string("sensorScope", fallback: "All")
        sensorScope = ["All", "CPU", "GPU", "Storage", "Battery", "PMU / other"].contains(sensor) ? sensor : "All"
        paneRankings = preferences.strings("paneRankings").filter { ResourcePane(rawValue: $0.key) != nil && ["cpu", "memory", "gpu", "ane", "neural", "disk", "read", "write"].contains($0.value) }
        if preferences.number("acceleratorRankingsVersion", fallback: 0) < 1 {
            paneRankings["gpu"] = "gpu"
            paneRankings["neural"] = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 ? "ane" : "neural"
            preferences.save(paneRankings, for: "paneRankings")
            preferences.save(1, for: "acceleratorRankingsVersion")
        }
    }
    var accessibleProcessCount: Int { resourceSample.count }
    var selectedProcessRecord: ProcessRow? { selection ?? trackedProcess }
    func activatePane(_ target: ResourcePane) {
        if pane != target { pane = target }
        page = target == .processes ? 0 : 1
        if target == .processes { arrange() }
        else {
            showingInspector = false; rows = []
            resourceSort = paneRankings[target.rawValue] ?? (target == .memory ? "memory" : target == .storage ? "disk" : target == .gpu ? "gpu" : target == .neural ? (ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 ? "ane" : "neural") : "cpu")
            rankResources()
        }
    }
    var historyCapacity: Int { min(601, Int(historySeconds / interval) + 1) }
    @Published var showingInspector = false
    @Published var showGPU = true { didSet { preferences.save(showGPU, for: "showGPU") } }
    @Published var showNeuralMemory = true { didSet { preferences.save(showNeuralMemory, for: "showNeuralMemory") } }
    @Published var showResident = false { didSet { preferences.save(showResident, for: "showResident") } }
    @Published var showDisk = false { didSet { preferences.save(showDisk, for: "showDisk") } }
    @Published var showUser = false { didSet { preferences.save(showUser, for: "showUser") } }
    var threadCount = 0
    let sampler = Sampler()
    @Published var visible = true
    func arrange() {
        let uid = getuid()
        let appIDs = scope == 2 ? Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)) : []
        rows = resourceSample.filter {
            (scope != 1 || $0.uid == uid) && (scope != 2 || appIDs.contains($0.id)) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.id).contains(search))
        }.sorted { processPrecedes($0, $1, key: sort, ascending: ascending) }
    }

    func run() async {
        guard !paused && visible else { await sampler.reset(); return }
        while !Task.isCancelled {
            if !paused && visible {
                if needsBaselineReset {
                    await sampler.reset()
                    needsBaselineReset = false
                }
                let gpu = (page == 0 && (showGPU || sort == "gpu" || showingInspector)) || pane == .gpu || (page != 0 && resourceSort == "gpu")
                let ane = pane == .neural || (page != 0 && resourceSort == "ane") || (page == 0 && showingInspector)
                let collect = gpu || ane || page == 0 || [.cpu, .memory, .storage].contains(pane) || overviewTick % 3 == 0
                overviewTick += 1
                let next = await sampler.read(includeProcesses: collect, includeHardware: true, includeSensorDetails: pane == .temperatures, includeGPU: gpu, includeANE: ane)
                guard !Task.isCancelled else { return }
                if needsBaselineReset { continue }
                var points = stagedHistory ?? history
                points.append(Point(cpu: next.cpu ?? .nan, memory: Double(next.used) / Double(max(1, next.total)) * 100,
                    beginsSegment: next.beginsInterval || (next.sampleDuration ?? 0) > interval * 2.5,
                    renderer: next.hardware.rendererUsage, tiler: next.hardware.tilerUsage, systemCPU: next.cpu == nil ? nil : next.systemCPU,
                    cores: next.cores, temperature: next.hardware.cpuTemperature, gpuTemperature: next.hardware.gpuTemperature,
                    batteryTemperature: next.hardware.batteryTemperature, batteryPercent: next.hardware.batteryPercent,
                    gpu: next.hardware.gpuUsage, aneWatts: next.hardware.aneWatts,
                    diskRead: next.hardware.diskRead, diskWrite: next.hardware.diskWrite,
                    download: next.download, upload: next.upload, cpuWatts: next.hardware.cpuWatts, gpuWatts: next.hardware.gpuWatts))
                let cutoff = ProcessInfo.processInfo.systemUptime - historySeconds
                if let first = points.first, first.time < cutoff { points.removeAll { $0.time < cutoff } }
                if points.count > 601 { points.removeFirst(points.count - 601) }
                if collect {
                    resourceSample = next.processes
                    lastProcessSampleDate = next.date
                    threadCount = next.processes.reduce(0) { $0 + Int($1.threads) }
                    recordSelected(next, time: points.last!.time)
                }
                if windowExposed { present(next, history: points) }
                else {
                    // Keep bounded, accurate monitoring history while a window is covered,
                    // without publishing changes that rebuild an invisible SwiftUI tree.
                    stagedSnapshot = next; stagedHistory = points
                }
                ProfileEvents.emit("sample", exposed: windowExposed, pane: (pane ?? .overview).rawValue)
            } else { await sampler.reset() }
            do { try await Task.sleep(for: .seconds(interval)) } catch { break }
        }
    }
    private func recordSelected(_ next: Snapshot, time: Double) {
        guard let selected else { return }
        if let row = next.processes.first(where: { $0.id == selected }) {
            let changed = trackedProcess?.id != row.id || trackedProcess?.birth != row.birth
            if changed { selectedSamples.removeAll(keepingCapacity: true) }
            trackedProcess = row
            selectedSamples.append(Point(cpu: row.cpu ?? .nan, memory: 0, time: time,
                processMemory: row.footprint.map { Double($0) },
                processGPUTime: row.gpuTime, processNeuralMemory: row.neuralMemory.map { Double($0) },
                beginsSegment: changed || next.beginsInterval || (next.sampleDuration ?? 0) > interval * 2.5))
        } else if let last = selectedSamples.last, last.cpu.isFinite || last.processMemory != nil {
            selectedSamples.append(Point(cpu: .nan, memory: 0, time: time, beginsSegment: true))
        }
        selectedSamples.removeAll { $0.time < time - 180 }
        if selectedSamples.count > 181 { selectedSamples.removeFirst(selectedSamples.count - 181) }
    }
    func invalidateRateBaselines() { needsBaselineReset = true }
    func systemDidWake() { invalidateRateBaselines() }
    func setWindowExposed(_ exposed: Bool) {
        guard exposed != windowExposed else { return }
        windowExposed = exposed
        ProfileEvents.emit("exposure", exposed: exposed, pane: (pane ?? .overview).rawValue)
        if exposed, let next = stagedSnapshot, let points = stagedHistory { present(next, history: points) }
    }
    private func present(_ next: Snapshot, history points: [Point]) {
        stagedSnapshot = nil; stagedHistory = nil
        snapshot = next; history = points
        if processHistory.last?.time != selectedSamples.last?.time || processHistory.count != selectedSamples.count { processHistory = selectedSamples }
        if resourceSampleDate != lastProcessSampleDate {
            resourceSampleDate = lastProcessSampleDate
            if pane == .overview || pane == nil { overviewProcesses = rankedProcesses(resourceSample, key: "cpu", limit: 5) }
            else if page != 0 { rankResources() }
        }
        if page == 0 { arrange() }
    }
    // The native outline sorts app families and their children itself. Keep one shared
    // source array here, rather than sorting a second full copy on every sample.
    func rankResources() {
        if pane == .overview || pane == nil { overviewProcesses = rankedProcesses(resourceSample, key: "cpu", limit: 5) }
        else { resourceLeaders = resourceSample }
    }
    func openProcess(_ row: ProcessRow) {
        search = ""; scope = 0; selected = row.id; sort = resourceSort == "ane" ? "neural" : resourceSort; ascending = false
        showingInspector = true; pane = .processes
    }
    func processRecord(_ pid: Int32) -> ProcessRow? { resourceSample.first { $0.id == pid } }
    var selection: ProcessRow? { selected.flatMap(processRecord) }
    func requestQuit(force: Bool) {
        guard let row = selection, row.id != getpid(), row.uid == getuid() else { return }
        let app = NSRunningApplication(processIdentifier: row.id)
        let alert = NSAlert()
        alert.messageText = "\(force ? "Force quit" : "Quit") \(row.name)?"
        alert.informativeText = force ? "Unsaved changes may be lost." : app == nil ? "This process will receive SIGTERM. Unsaved work may be lost." : "The app will receive a request to quit normally."
        alert.addButton(withTitle: force ? "Force quit" : "Quit"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            // Recheck the process identity after confirmation to avoid PID reuse.
            guard selection?.birth == row.birth, tg_matches(row.id, row.birth) != 0 else { return }
            let success: Bool
            if let app { success = force ? app.forceTerminate() : app.terminate() }
            else { success = tg_terminate(row.id, row.birth, force ? 1 : 0) != 0 }
            if !success { let failure = NSAlert(); failure.messageText = "macOS could not quit this app."; failure.runModal() }
        }
    }
}
