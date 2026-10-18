import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(AppEnv.headless ? .prohibited : .regular)
app.run()
