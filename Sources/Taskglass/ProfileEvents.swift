import Foundation

/// Opt-in development diagnostics. No process names, readings or history are
/// written. Launch the binary with --profile-events and redirect stderr locally.
enum ProfileEvents {
    static let enabled = CommandLine.arguments.contains("--profile-events")
    static func emit(_ kind: String, exposed: Bool, pane: String) {
        guard enabled else { return }
        let line = "TG_PROFILE t=\(ProcessInfo.processInfo.systemUptime) event=\(kind) exposed=\(exposed ? 1 : 0) pane=\(pane)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
