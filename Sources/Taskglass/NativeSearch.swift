import SwiftUI
import AppKit

struct NativeSearch: NSViewRepresentable {
    @ObservedObject var monitor: Monitor
    func makeCoordinator() -> Coordinator { Coordinator(monitor) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search processes"
        field.controlSize = .regular
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.setAccessibilityLabel("Search processes by name or PID")
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != monitor.search { field.stringValue = monitor.search }
    }
    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        let monitor: Monitor
        init(_ monitor: Monitor) { self.monitor = monitor }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            monitor.search = field.stringValue
        }
    }
}
