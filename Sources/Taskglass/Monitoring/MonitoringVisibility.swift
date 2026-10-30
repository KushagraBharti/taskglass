import SwiftUI
import AppKit

/// Scope exposure to this app's actual content window. Covered windows keep
/// sampling/history; only visible presentation is deferred. Hide/minimize still
/// use the existing complete pause behavior in ContentView.
struct MonitoringVisibility: NSViewRepresentable {
    let monitor: Monitor
    func makeNSView(context: Context) -> ExposureView {
        let view = ExposureView(); view.monitor = monitor
        return view
    }
    func updateNSView(_ nsView: ExposureView, context: Context) { nsView.monitor = monitor }
    static func dismantleNSView(_ nsView: ExposureView, coordinator: ()) {
        nsView.monitor?.invalidateRateBaselines()
        nsView.stop()
    }

    @MainActor final class ExposureView: NSView {
        weak var monitor: Monitor?
        private var observations: [(NotificationCenter, NSObjectProtocol)] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            let center = NotificationCenter.default
            observations.append((center, center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.report() }
            }))
            observations.append((center, center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.monitor?.visible = false
                    self?.monitor?.invalidateRateBaselines()
                    self?.monitor?.setWindowExposed(false)
                }
            }))
            observations.append((center, center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.report() }
            }))
            let workspace = NSWorkspace.shared.notificationCenter
            observations.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.monitor?.systemDidWake() }
            }))
            DispatchQueue.main.async { [weak self] in self?.report() }
        }
        func stop() {
            observations.forEach { $0.0.removeObserver($0.1) }
            observations.removeAll()
        }
        private func report() {
            guard let window else { return }
            let exposed = window.occlusionState.contains(.visible)
            if exposed && window.isVisible && !window.isMiniaturized && !NSApplication.shared.isHidden && monitor?.visible == false {
                monitor?.visible = true
            }
            monitor?.setWindowExposed(exposed)
        }
    }
}
