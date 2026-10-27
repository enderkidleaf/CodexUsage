import AppKit

// 离线渲染验证：把面板挂到真实 NSWindow（不显示）以保证 Auto Layout 与
// 语义颜色完整生效，再将 contentView 绘制为 PNG，绕开当前会话的屏幕捕获限制
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = RenderDelegate(outputPath: CommandLine.arguments[1])
    app.delegate = delegate
    app.run()
}

@MainActor
final class RenderDelegate: NSObject, NSApplicationDelegate {
    let outputPath: String
    var store: RefreshStore!
    var window: NSWindow!

    init(outputPath: String) { self.outputPath = outputPath }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = RefreshStore()
        let controller = PanelController(store: store)
        window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 340, height: 440))
        window.styleMask = [.borderless]
        // 强制浅色外观，保证离线渲染时语义颜色（labelColor 等）可被正确解析
        window.appearance = NSAppearance(named: .aqua)
        store.start()

        Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.render(controller: controller)
        }
    }

    private func render(controller: PanelController) {
        let v = controller.view
        v.layoutSubtreeIfNeeded()
        let fit = v.fittingSize
        let h = ceil(fit.height)
        v.setFrameSize(NSSize(width: 340, height: h))
        window.setContentSize(NSSize(width: 340, height: h))
        v.layoutSubtreeIfNeeded()
        dumpTree(v, depth: 0)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(v.bounds.width),
            pixelsHigh: Int(v.bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("FAIL: no bitmap rep"); NSApp.terminate(nil); return
        }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        // 先铺一层不透明背景，与 .aqua 外观保持一致
        NSColor.white.setFill()
        v.bounds.fill()
        v.layer?.render(in: ctx.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("FAIL: png encode"); NSApp.terminate(nil); return
        }
        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
            print("OK rendered 340x\(h) fit=\(fit) -> \(outputPath)")
        } catch {
            print("FAIL write: \(error)")
        }
        NSApp.terminate(nil)
    }

    private func dumpTree(_ view: NSView, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        let f = view.frame
        let text = (view as? NSTextField)?.stringValue ?? ""
        var bg = "nil"
        if let cg = view.layer?.backgroundColor, let c = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
            bg = String(format: "bg=%.2f,%.2f,%.2f,a%.2f", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        print(String(format: "\(pad)%@ frame=(%.0f,%.0f,%.0f,%.0f) hidden=\(view.isHidden) alpha=\(view.alphaValue) \(bg) \(text)",
                     String(describing: type(of: view)), f.origin.x, f.origin.y, f.size.width, f.size.height))
        view.subviews.forEach { dumpTree($0, depth: depth + 1) }
    }
}
