import AppKit

// AppKit 应用必须在主线程启动，据此进入 MainActor 隔离上下文
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
