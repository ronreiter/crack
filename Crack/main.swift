import AppKit

// Pure AppKit app - no SwiftUI
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
