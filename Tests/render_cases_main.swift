import AppKit

// 错误态 / 达限态 / 深色模式的多场景离线渲染验证（不发真实网络请求，直接注入 store 状态）
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = CasesDelegate(outputDir: CommandLine.arguments[1])
    app.delegate = delegate
    app.run()
}

@MainActor
final class CasesDelegate: NSObject, NSApplicationDelegate {
    let outputDir: String
    var index = 0

    struct Case {
        let name: String
        let dark: Bool
        let configure: (RefreshStore) -> Void
    }

    lazy var cases: [Case] = {
        let now = Int(Date().timeIntervalSince1970)
        let reachedUsage = WhamUsage(
            planType: "plus",
            rateLimit: .init(allowed: true, limitReached: true,
                             primaryWindow: .init(usedPercent: 100, limitWindowSeconds: 18000,
                                                  resetAfterSeconds: 3200, resetAt: now + 3200),
                             secondaryWindow: .init(usedPercent: 16, limitWindowSeconds: 604800,
                                                    resetAfterSeconds: 600000, resetAt: now + 600000)),
            modelUsage: nil,
            credits: .init(hasCredits: false, unlimited: false, overageLimitReached: false, balance: "0"),
            rateLimitResetCredits: .init(availableCount: 2, applicableAvailableCount: 2),
            rateLimitReachedType: nil, rateLimitUpsell: nil)
        let normalUsage = WhamUsage(
            planType: "plus",
            rateLimit: .init(allowed: true, limitReached: false,
                             primaryWindow: .init(usedPercent: 0, limitWindowSeconds: 18000,
                                                  resetAfterSeconds: 17990, resetAt: now + 17990),
                             secondaryWindow: .init(usedPercent: 16, limitWindowSeconds: 604800,
                                                    resetAfterSeconds: 600000, resetAt: now + 600000)),
            modelUsage: nil,
            credits: .init(hasCredits: false, unlimited: false, overageLimitReached: false, balance: "0"),
            rateLimitResetCredits: .init(availableCount: 2, applicableAvailableCount: 2),
            rateLimitReachedType: nil, rateLimitUpsell: nil)
        let tokens = TokenAggregate(inputTokens: 5_127_242, cachedInputTokens: 5_044_736,
                                    outputTokens: 30_260, reasoningTokens: 0,
                                    totalTokens: 5_157_502, recordCount: 52)
        return [
            Case(name: "1_token_expired", dark: false) { s in
                s.fetchError = .tokenExpired(nil)
            },
            Case(name: "2_network_error", dark: false) { s in
                s.fetchError = .network("无法连接到服务器（模拟离线）")
            },
            Case(name: "3_limit_reached", dark: false) { s in
                s.usage = reachedUsage
                s.todayTokens = tokens
                s.lastRemoteUpdate = Date()
                s.lastLocalUpdate = Date()
            },
            Case(name: "4_dark_normal", dark: true) { s in
                s.usage = normalUsage
                s.todayTokens = tokens
                s.lastRemoteUpdate = Date()
                s.lastLocalUpdate = Date()
            },
            Case(name: "5_limit_remaining_mode", dark: false) { s in
                s.usage = reachedUsage
                s.todayTokens = tokens
                s.lastRemoteUpdate = Date()
                s.lastLocalUpdate = Date()
            }
        ]
    }()

    init(outputDir: String) { self.outputDir = outputDir }

    func applicationDidFinishLaunching(_ notification: Notification) {
        runNext()
    }

    private func runNext() {
        guard index < cases.count else {
            print("ALL_CASES_DONE")
            NSApp.terminate(nil)
            return
        }
        let c = cases[index]
        let store = RefreshStore()
        let controller = PanelController(store: store)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.borderless]
        window.appearance = NSAppearance(named: c.dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 340, height: 460))
        c.configure(store)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.render(controller: controller, dark: c.dark, name: c.name)
        }
    }

    private func render(controller: PanelController, dark: Bool, name: String) {
        let v = controller.view
        // 剩余模式场景：模拟点击百分比按钮，切换到"已用/剩余"模式
        if name.contains("remaining") {
            tapPercentButtons(v)
        }
        v.layoutSubtreeIfNeeded()
        let h = ceil(v.fittingSize.height)
        v.setFrameSize(NSSize(width: 340, height: h))
        controller.view.window?.setContentSize(NSSize(width: 340, height: h))
        v.layoutSubtreeIfNeeded()
        print("---- CASE \(name) ----")
        dumpTree(v, depth: 0)
        // 等待一个 RunLoop 周期，让 CoreAnimation 提交位移后的 layer geometry
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.capture(controller: controller, dark: dark, name: name)
        }
    }

    private func capture(controller: PanelController, dark: Bool, name: String) {
        let v = controller.view
        v.layoutSubtreeIfNeeded()
        let h = Int(v.bounds.height)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 340, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            print("FAIL bitmap \(name)"); NSApp.terminate(nil); return
        }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        if dark {
            NSColor(srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1).setFill()
        } else {
            NSColor.white.setFill()
        }
        v.bounds.fill()
        v.layer?.render(in: ctx.cgContext)
        NSGraphicsContext.restoreGraphicsState()

        let url = URL(fileURLWithPath: outputDir).appendingPathComponent("\(name).png")
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("OK \(name) 340x\(h)")
        } else {
            print("FAIL encode \(name)")
        }
        index += 1
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            self?.runNext()
        }
    }

    @discardableResult
    private func tapPercentButtons(_ view: NSView) -> Bool {
        // 两个窗口共用一个全局开关，点一次即可；找到第一个百分比按钮后停止遍历
        if let b = view as? NSButton, b.title.contains("%"),
           let action = b.action {
            _ = NSApp.sendAction(action, to: b.target, from: b)
            return true
        }
        for sub in view.subviews where tapPercentButtons(sub) {
            return true
        }
        return false
    }

    private func dumpTree(_ view: NSView, depth: Int) {
        let pad = String(repeating: " ", count: depth)
        let f = view.frame
        let text = (view as? NSTextField)?.stringValue ?? ""
        print(String(format: "\(pad)%@ x=%.0f y=%.0f w=%.0f h=%.0f hidden=\(view.isHidden) \(text)",
                     String(describing: type(of: view)), f.origin.x, f.origin.y, f.size.width, f.size.height))
        view.subviews.forEach { dumpTree($0, depth: depth + 1) }
    }
}
