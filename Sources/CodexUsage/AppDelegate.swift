import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = RefreshStore()
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 440)
        popover.contentViewController = PanelController(store: store)

        store.start()
        bindStatusButton()
    }

    // MARK: - 状态栏按钮

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Codex 用量")
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.font = .systemFont(ofSize: 12, weight: .medium)
    }

    private func bindStatusButton() {
        Publishers.CombineLatest3(store.$usage, store.$fetchError, store.$now)
            .receive(on: RunLoop.main)
            .sink { [weak self] usage, error, _ in
                self?.updateStatusButton(usage: usage, error: error)
            }
            .store(in: &cancellables)
        updateStatusButton(usage: nil, error: nil)
    }

    private func updateStatusButton(usage: WhamUsage?, error: UsageFetchError?) {
        guard let button = statusItem.button else { return }
        let percent = usage?.rateLimit?.primaryWindow?.usedPercent
        let reached = usage?.rateLimit?.limitReached == true

        let color: NSColor
        if error != nil && usage == nil {
            color = .systemOrange
        } else if reached {
            color = .systemRed
        } else {
            color = Format.percentColor(percent)
        }

        let label: String
        if let p = percent {
            label = " \(p)%"
        } else if error != nil && usage == nil {
            label = " !"
        } else {
            label = " …"
        }
        button.title = label
        button.contentTintColor = color
        button.attributedTitle = NSAttributedString(string: label, attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ])
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            removeEventMonitor()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installEventMonitor()
        }
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.popover.performClose(nil)
                self?.removeEventMonitor()
            }
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
