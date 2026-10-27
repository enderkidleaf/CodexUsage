import AppKit
import Combine

// MARK: - 面板控制器（纯 AppKit 代码布局）

final class PanelController: NSViewController {
    private let store: RefreshStore
    private var bag = Set<AnyCancellable>()
    /// true 时窗口百分比按"剩余量"显示，false 按"已用量"显示；点击卡片百分比切换
    private var showRemaining = false

    // 头部
    private let statusDot = DotView()
    private let titleLabel = PanelController.label(font: .systemFont(ofSize: 14, weight: .bold))
    private let planBadge = PanelController.label(font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor)

    // 达限横幅
    private let bannerBox = TintBox(tint: .systemRed, alpha: 0.10)
    private let bannerTitle = PanelController.label(font: .systemFont(ofSize: 12, weight: .semibold), color: .systemRed)
    private let bannerDetail = PanelController.label(font: .systemFont(ofSize: 11),
                                                     color: .secondaryLabelColor, wraps: true)

    // 窗口
    private let primaryBar = WindowBarView()
    private let secondaryBar = WindowBarView()

    // Credits
    private let creditsLabel = PanelController.label(font: .systemFont(ofSize: 11), color: .labelColor)
    private let resetCreditsLabel = PanelController.label(font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

    // 今日 token
    private let responseCountLabel = PanelController.label(font: .systemFont(ofSize: 10), color: .secondaryLabelColor)
    private let metricTotal = MetricView()
    private let metricOutput = MetricView()
    private let metricInput = MetricView()
    private let metricCached = MetricView()
    private let noSessionLabel = PanelController.label(font: .systemFont(ofSize: 11), color: .secondaryLabelColor)

    // 错误
    private let errorBox = TintBox(tint: .systemOrange, alpha: 0.08)
    private let errorTitle = PanelController.label(font: .systemFont(ofSize: 12, weight: .semibold), color: .systemOrange)
    private let errorDetail = PanelController.label(font: .systemFont(ofSize: 11),
                                                    color: .secondaryLabelColor, wraps: true)

    // 底部
    private let launchSwitch = NSSwitch()
    private let updatedLabel = PanelController.label(font: .systemFont(ofSize: 10), color: .tertiaryLabelColor)
    private let sourceLabel = PanelController.label(font: .systemFont(ofSize: 10), color: .tertiaryLabelColor)

    init(store: RefreshStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 440))
        view.widthAnchor.constraint(equalToConstant: 340).isActive = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        bind()
        render()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let fit = view.fittingSize
        let target = NSSize(width: 340, height: ceil(fit.height))
        if target != preferredContentSize {
            preferredContentSize = target
        }
    }

    // MARK: - 布局

    private func buildLayout() {
        view.wantsLayer = true
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])

        // 头部
        let header = NSStackView(views: [statusDot, titleLabel, planBadge, flexibleSpacer(), makeRefreshButton()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        statusDot.wantsLayer = true
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 10),
            statusDot.heightAnchor.constraint(equalToConstant: 10)
        ])
        root.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        // 错误横幅
        setupErrorBox()
        root.addArrangedSubview(errorBox)
        errorBox.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        // 达限横幅
        setupBannerBox()
        root.addArrangedSubview(bannerBox)
        bannerBox.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        // 窗口条
        let bars = NSStackView(views: [primaryBar, secondaryBar])
        bars.orientation = .vertical
        bars.spacing = 10
        root.addArrangedSubview(bars)
        bars.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        // Credits
        let creditsRow = NSStackView(views: [creditsLabel, flexibleSpacer(), resetCreditsLabel])
        creditsRow.orientation = .horizontal
        creditsRow.spacing = 8
        root.addArrangedSubview(creditsRow)
        creditsRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        root.addArrangedSubview(NSBox.separator())

        // 今日 token
        let tokenHeader = NSStackView(views: [
            label(text: "今日本地 Token", font: .systemFont(ofSize: 12, weight: .semibold)),
            flexibleSpacer(),
            responseCountLabel
        ])
        tokenHeader.orientation = .horizontal
        root.addArrangedSubview(tokenHeader)
        tokenHeader.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let grid = NSGridView(views: [
            [metricTotal, metricOutput],
            [metricInput, metricCached]
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 6
        grid.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.addArrangedSubview(noSessionLabel)

        root.addArrangedSubview(NSBox.separator())

        // 底部控制
        let launchRow = NSStackView(views: [
            label(text: "开机启动", font: .systemFont(ofSize: 11)),
            launchSwitch,
            flexibleSpacer(),
            makeLinkButton("网页用量", action: #selector(openUsageWeb)),
            makeLinkButton("退出", action: #selector(quit))
        ])
        launchRow.orientation = .horizontal
        launchRow.alignment = .centerY
        launchRow.spacing = 8
        launchSwitch.target = self
        launchSwitch.action = #selector(launchToggled)
        root.addArrangedSubview(launchRow)
        launchRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let metaRow = NSStackView(views: [updatedLabel, flexibleSpacer(), sourceLabel])
        metaRow.orientation = .horizontal
        root.addArrangedSubview(metaRow)
        metaRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        sourceLabel.stringValue = "数据源：本机 Codex"

        // 所有内容按固有尺寸排列，防止自定义视图在 stack 中被均分拉伸
        enforceIntrinsicSizes(root)
    }

    private func enforceIntrinsicSizes(_ view: NSView) {
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        view.subviews.forEach(enforceIntrinsicSizes)
    }

    private func setupBannerBox() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.octagon.fill",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemRed
        let texts = NSStackView(views: [bannerTitle, bannerDetail])
        texts.orientation = .vertical
        texts.spacing = 2
        texts.setHuggingPriority(.defaultLow, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [icon, texts])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        bannerBox.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bannerBox.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: bannerBox.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: bannerBox.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bannerBox.bottomAnchor, constant: -8)
        ])
    }

    private func setupErrorBox() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "wifi.exclamationmark",
                                              accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        errorTitle.stringValue = "无法获取在线用量"
        let texts = NSStackView(views: [errorTitle, errorDetail])
        texts.orientation = .vertical
        texts.spacing = 3
        texts.setHuggingPriority(.defaultLow, for: .horizontal)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [icon, texts])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        errorBox.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: errorBox.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: errorBox.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: errorBox.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: errorBox.bottomAnchor, constant: -8)
        ])
    }

    private func makeRefreshButton() -> NSView {
        let btn = NSButton()
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.target = self
        btn.action = #selector(refresh)
        if let img = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新") {
            btn.image = img
            btn.contentTintColor = .secondaryLabelColor
        }
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.widthAnchor.constraint(equalToConstant: 22).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return btn
    }

    private func makeLinkButton(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    // MARK: - 数据绑定

    private func bind() {
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.render() }
            .store(in: &bag)
        store.$launchAtLogin
            .receive(on: RunLoop.main)
            .sink { [weak self] on in self?.launchSwitch.state = on ? .on : .off }
            .store(in: &bag)
    }

    private func render() {
        titleLabel.stringValue = "Codex 用量"
        planBadge.stringValue = " \(store.planDisplayName) "
        planBadge.isHidden = store.usage == nil

        let error = store.fetchError
        let hasUsage = store.usage != nil
        errorBox.isHidden = !(error != nil && !hasUsage)
        errorDetail.stringValue = error?.errorDescription ?? ""

        let reached = store.limitReached
        bannerBox.isHidden = !reached
        bannerTitle.stringValue = "已达到当前用量上限"
        bannerDetail.stringValue = resumeText() ?? ""

        statusDot.layer?.backgroundColor = dotColor(reached: reached, error: error, hasUsage: hasUsage).cgColor
        statusDot.needsDisplay = true

        primaryBar.update(title: "短期窗口", icon: "bolt.fill",
                          window: store.primary, now: store.now, showRemaining: showRemaining)
        secondaryBar.update(title: "周窗口", icon: "calendar",
                            window: store.secondary, now: store.now, showRemaining: showRemaining)
        primaryBar.onToggle = { [weak self] in self?.toggleDisplayMode() }
        secondaryBar.onToggle = { [weak self] in self?.toggleDisplayMode() }

        renderCredits()
        renderTokens()
        renderFooter()
    }

    private func renderCredits() {
        if let c = store.usage?.credits {
            if c.unlimited == true {
                creditsLabel.stringValue = "Credits：无限"
            } else {
                creditsLabel.stringValue = "Credits 余额：\(c.balance ?? "0")"
            }
        } else {
            creditsLabel.stringValue = "Credits：—"
        }
        if let n = store.usage?.rateLimitResetCredits?.availableCount {
            resetCreditsLabel.stringValue = "额度重置次数：\(n)"
        } else {
            resetCreditsLabel.stringValue = ""
        }
    }

    private func renderTokens() {
        let t = store.todayTokens
        let hasData = (t?.totalTokens ?? 0) > 0
        noSessionLabel.isHidden = hasData
        noSessionLabel.stringValue = "今天还没有 Codex 会话记录"
        if let t {
            responseCountLabel.stringValue = "\(Format.full(t.recordCount)) 次响应"
            metricTotal.configure(name: "总计", value: Format.compact(t.totalTokens), emphasized: true)
            metricOutput.configure(name: "输出", value: Format.compact(t.outputTokens))
            metricInput.configure(name: "输入", value: Format.compact(t.inputTokens))
            metricCached.configure(name: "其中缓存", value: Format.compact(t.cachedInputTokens))
        }
        [metricTotal, metricOutput, metricInput, metricCached].forEach { $0.isHidden = !hasData }
        responseCountLabel.isHidden = !hasData
    }

    private func renderFooter() {
        if let d = store.lastRemoteUpdate {
            updatedLabel.stringValue = "更新于 \(Format.clock(d))"
        } else {
            updatedLabel.stringValue = "尚未成功更新"
        }
    }

    private func resumeText() -> String? {
        if let ts = store.usage?.rateLimitUpsell?.resetAt {
            return "预计 \(Format.clockWithDay(Date(timeIntervalSince1970: TimeInterval(ts)))) 后恢复"
        }
        if let at = store.usage?.modelUsage?.values.first?.availableAt,
           let date = parseISO(at) {
            return "预计 \(Format.clockWithDay(date)) 恢复可用"
        }
        if let resetAt = store.primary?.resetAt {
            return "窗口重置：\(Format.clock(Date(timeIntervalSince1970: TimeInterval(resetAt))))"
        }
        return nil
    }

    private func dotColor(reached: Bool, error: UsageFetchError?, hasUsage: Bool) -> NSColor {
        if error != nil && !hasUsage { return .systemOrange }
        if reached { return .systemRed }
        return .systemGreen
    }

    private func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    // MARK: - 动作

    private func toggleDisplayMode() {
        showRemaining.toggle()
        render()
    }

    @objc private func refresh() {
        Task { await store.refreshRemote() }
        Task { await store.refreshLocal() }
    }

    @objc private func openUsageWeb() {
        if let url = URL(string: AppRelativePath.usageWebURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func launchToggled() {
        let on = launchSwitch.state == .on
        store.toggleLaunchAtLogin(on)
    }

    // MARK: - 控件工厂

    private static func label(text: String = "",
                              font: NSFont = .systemFont(ofSize: 12),
                              color: NSColor = .labelColor,
                              wraps: Bool = false) -> NSTextField {
        let l = IntrinsicLabel()
        l.stringValue = text
        l.font = font
        l.textColor = color
        l.wraps = wraps
        l.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        l.maximumNumberOfLines = wraps ? 0 : 1
        if !wraps {
            // 单行信息锁定固有宽度，弹性留白只由 spacer 承担
            l.setContentHuggingPriority(.required, for: .horizontal)
            l.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        return l
    }

    private func label(text: String, font: NSFont) -> NSTextField {
        Self.label(text: text, font: font)
    }

    private func flexibleSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.widthAnchor.constraint(greaterThanOrEqualToConstant: 4).isActive = true
        return v
    }
}

// MARK: - 状态圆点

private final class DotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 窗口用量条

private final class WindowBarView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let percentButton = NSButton()
    private let progress = ColoredProgressBar()
    private let resetLabel = NSTextField(labelWithString: "")
    private let countdownLabel = NSTextField(labelWithString: "")

    /// 点击百分比区域时回调，由控制器翻转"已用/剩余"显示模式
    var onToggle: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .labelColor
        percentButton.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        percentButton.bezelStyle = .inline
        percentButton.isBordered = false
        percentButton.target = self
        percentButton.action = #selector(percentTapped)
        percentButton.toolTip = "点击切换：已用 / 剩余"
        percentButton.setContentHuggingPriority(.required, for: .horizontal)
        resetLabel.font = .systemFont(ofSize: 10)
        resetLabel.textColor = .tertiaryLabelColor
        countdownLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        countdownLabel.textColor = .secondaryLabelColor
        iconView.contentTintColor = .secondaryLabelColor

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 8).isActive = true

        let head = NSStackView(views: [iconView, titleLabel, flexibleSpacer(), percentButton])
        head.orientation = .horizontal
        head.alignment = .centerY
        head.spacing = 6
        let foot = NSStackView(views: [resetLabel, flexibleSpacer(), countdownLabel])
        foot.orientation = .horizontal
        let root = NSStackView(views: [head, progress, foot])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 5
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
            progress.widthAnchor.constraint(equalTo: root.widthAnchor),
            heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    func update(title: String, icon: String, window: WhamUsage.RateWindow?, now: Date, showRemaining: Bool) {
        guard let w = window else {
            isHidden = true
            return
        }
        isHidden = false
        iconView.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        let used = w.usedPercent ?? 0
        let shown = showRemaining ? max(0, 100 - used) : used
        var t = title
        if let secs = w.limitWindowSeconds {
            t += " · \(Format.windowLength(seconds: secs))"
        }
        titleLabel.stringValue = t
        percentButton.title = showRemaining ? "剩 \(shown)%" : "\(shown)%"
        let color = Format.percentColor(shown)
        percentButton.contentTintColor = color
        progress.set(percent: shown, color: color)
        if let resetAt = w.resetAt {
            resetLabel.stringValue = "重置 \(Format.clock(Date(timeIntervalSince1970: TimeInterval(resetAt))))"
        } else {
            resetLabel.stringValue = ""
        }
        countdownLabel.stringValue = "剩余 \(Format.countdown(until: w.resetAt, now: now))"
    }

    @objc private func percentTapped() {
        onToggle?()
    }

    private func flexibleSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
}

// MARK: - Token 指标卡

private final class MetricView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.10).cgColor
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .labelColor
        let row = NSStackView(views: [nameLabel, flexibleSpacer(), valueLabel])
        row.orientation = .horizontal
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            heightAnchor.constraint(equalToConstant: 26)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.10).cgColor
        }
    }

    func configure(name: String, value: String, emphasized: Bool = false) {
        nameLabel.stringValue = name
        valueLabel.stringValue = value
        valueLabel.font = emphasized
            ? .monospacedSystemFont(ofSize: 12, weight: .semibold)
            : .monospacedSystemFont(ofSize: 11, weight: .medium)
    }

    private func flexibleSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }
}

// MARK: - 带主题色底色的容器视图（随外观自动刷新）

private final class TintBox: NSView {
    private let tint: NSColor
    private let alpha: CGFloat

    init(tint: NSColor, alpha: CGFloat) {
        self.tint = tint
        self.alpha = alpha
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        applyTint()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTint()
    }

    private func applyTint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tint.withAlphaComponent(alpha).cgColor
        }
    }
}

// MARK: - 自定义着色进度条

private final class ColoredProgressBar: NSView {
    private let fill = NSView()
    private var fillWidth: NSLayoutConstraint!
    private var percent: Int = 0
    private var fillColor: NSColor = .systemGreen

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 4
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)
        fillWidth = fill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            fillWidth
        ])
        resolveColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        fillWidth.constant = bounds.width * CGFloat(percent) / 100.0
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        resolveColors()
    }

    private func resolveColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5,
                                         alpha: isDark ? 0.28 : 0.22).cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill.layer?.backgroundColor = fillColor.cgColor
        }
    }

    func set(percent: Int, color: NSColor) {
        self.percent = max(0, min(100, percent))
        self.fillColor = color
        fill.isHidden = self.percent <= 0
        resolveColors()
        needsLayout = true
    }
}

// MARK: - 工具扩展

private extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}

// MARK: - 精确固有宽度文本标签

/// NSTextField 在截断/换行模式下自报的 intrinsicContentSize 对中英混排会偏窄或缺失，
/// 这里直接按字符串真实绘制尺寸计算固有宽度，保证横排信息既不被 spacer 压缩也不被截断。
private final class IntrinsicLabel: NSTextField {
    var wraps: Bool = false

    init() {
        super.init(frame: .zero)
        isBezeled = false
        isBordered = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override var stringValue: String {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        guard let font else { return super.intrinsicContentSize }
        if wraps {
            // 多行文案：宽度跟随容器，高度交给 cell 按实际宽度换行计算
            var size = super.intrinsicContentSize
            size.width = NSView.noIntrinsicMetric
            return size
        }
        guard !stringValue.isEmpty else { return super.intrinsicContentSize }
        let textSize = (stringValue as NSString).size(withAttributes: [.font: font])
        return NSSize(width: ceil(textSize.width) + 2, height: ceil(textSize.height))
    }
}
