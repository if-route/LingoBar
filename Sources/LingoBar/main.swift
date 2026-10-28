import AppKit

// A child CLI that exits before reading stdin must not kill the app with SIGPIPE.
signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments
if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}
if arguments.contains("--e2e") {
    EndToEnd.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
