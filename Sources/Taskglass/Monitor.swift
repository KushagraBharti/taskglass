import SwiftUI
import AppKit
import SystemProbe

@MainActor final class Monitor: ObservableObject {
    @Published var snapshot = Snapshot()
    @Published var history: [Point] = []
    @Published var search = ""
    @Published var interval = 2.0
    @Published var paused = false
    @Published var selected: Int32?
    @Published var scope = 0
    @Published var sort = "memory"
    @Published var ascending = false
    @Published var rows: [ProcessRow] = []
    @Published var inspect = false
    @Published var page = 0
    @Published var showingInspector = false
    @Published var showResident = false
    @Published var showDisk = false
    @Published var showUser = false
    var threadCount = 0
    let sampler = Sampler()
    @Published var visible = true
    func arrange() {
        let uid = getuid()
        let appIDs = scope == 2 ? Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier)) : []
        rows = snapshot.processes.filter {
            (scope != 1 || $0.uid == uid) && (scope != 2 || appIDs.contains($0.id)) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.id).contains(search))
        }.sorted { processPrecedes($0, $1, key: sort, ascending: ascending) }
    }

    func run() async {
        guard !paused && visible else { await sampler.reset(); return }
        while !Task.isCancelled {
            if !paused && visible {
                let next = await sampler.read(includeProcesses: page == 0)
                guard !Task.isCancelled else { return }
                snapshot = next
                threadCount = next.processes.reduce(0) { $0 + Int($1.threads) }
                if let cpu = snapshot.cpu {
                    history.append(Point(cpu: cpu, memory: Double(snapshot.used) / Double(max(1, snapshot.total)) * 100))
                    if history.count > 90 { history.removeFirst(history.count - 90) }
                }
                if page == 0 { arrange() }
            } else { await sampler.reset() }
            do { try await Task.sleep(for: .seconds(interval)) } catch { break }
        }
    }
    var selection: ProcessRow? { snapshot.processes.first { $0.id == selected } }
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
