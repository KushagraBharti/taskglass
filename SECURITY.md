# Security

Taskglass reads system counters locally. It has no privileged helper, login item,
telemetry service, updater daemon or runtime network dependency. It can request
termination only for your own processes, and rechecks PID/start identity before
acting. macOS may deny access to protected processes or hardware sources.

Please report security issues through this repository's private vulnerability
reporting feature. Avoid posting sensitive process names, executable paths,
account information or diagnostic logs in a public issue.

The first release is an unsigned preview. An ad-hoc bundle signature verifies
bundle integrity; it does not identify the publisher to Gatekeeper. Downloads
are accompanied by SHA-256 checksums and CI build provenance. Never disable
Gatekeeper globally to install Taskglass.

Private SMC/IOReport interfaces are optional and version-dependent. Unsupported
or invalid data should remain unavailable, rather than being inferred as zero.
