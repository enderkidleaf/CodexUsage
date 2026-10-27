import AppKit
import Combine

// 仅用于截图验证：把面板放进普通窗口展示（正式产物为 NSPopover）
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let delegate = PreviewDelegate()
    app.delegate = delegate
    app.run()
}

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var store: RefreshStore!
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = RefreshStore()
        let controller = PanelController(store: store)
        window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 340, height: 560))
        window.styleMask = [.titled, .closable]
        window.title = "Codex 用量面板预览"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        store.start()
    }
}
