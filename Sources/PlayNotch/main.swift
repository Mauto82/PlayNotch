import AppKit

// PlayNotch runs as an "agent" app: no Dock icon, only a menu-bar item.
// The Info.plist sets LSUIElement, but we also enforce .accessory here
// so it behaves correctly even when launched from the raw binary.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()
