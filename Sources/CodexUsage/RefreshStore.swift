import Foundation
import Combine
import AppKit

@MainActor
final class RefreshStore: ObservableObject {

    @Published var usage: WhamUsage?
    @Published var todayTokens: TokenAggregate?
    @Published var fetchError: UsageFetchError?
    @Published var lastRemoteUpdate: Date?
    @Published var lastLocalUpdate: Date?
    @Published var now = Date()
    @Published var isRefreshing = false
    @Published var launchAtLogin = false

    private let api = UsageAPI()
    private let scanner = TokenUsageScanner()
    private var tasks = Set<AnyCancellable>()

    // 远程用量轮询间隔（秒）
    var remoteInterval: TimeInterval = 60
    // 本地 token 扫描间隔（秒）
    var localInterval: TimeInterval = 120

    func start() {
        launchAtLogin = LaunchItemHelper.isEnabled()

        Task { await refreshRemote() }
        Task { await refreshLocal() }

        Timer.publish(every: remoteInterval, tolerance: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refreshRemote() }
            }
            .store(in: &tasks)

        Timer.publish(every: localInterval, tolerance: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refreshLocal() }
            }
            .store(in: &tasks)

        // 每秒 tick，仅用于倒计时显示
        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.now = date
            }
            .store(in: &tasks)
    }

    func refreshRemote() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let result = try await api.fetchUsage()
            self.usage = result
            self.fetchError = nil
            self.lastRemoteUpdate = Date()
        } catch let error as UsageFetchError {
            self.fetchError = error
        } catch {
            self.fetchError = .network(error.localizedDescription)
        }
    }

    func refreshLocal() async {
        let agg = await scanner.scanToday()
        self.todayTokens = agg
        self.lastLocalUpdate = Date()
    }

    func toggleLaunchAtLogin(_ on: Bool) {
        launchAtLogin = LaunchItemHelper.setEnabled(on)
    }

    // MARK: - 视图派生数据

    var primary: WhamUsage.RateWindow? { usage?.rateLimit?.primaryWindow }
    var secondary: WhamUsage.RateWindow? { usage?.rateLimit?.secondaryWindow }

    var limitReached: Bool { usage?.rateLimit?.limitReached == true }

    /// 状态栏按钮展示用的主窗口百分比（无数据时返回 nil）
    var statusPercent: Int? { primary?.usedPercent }

    var planDisplayName: String {
        guard let plan = usage?.planType, !plan.isEmpty else { return "Codex" }
        return plan.uppercased()
    }
}

// MARK: - 格式化工具

enum Format {
    static func compact(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        let n = NSNumber(value: value)
        if value >= 1_000_000_000 {
            return f.string(from: NSNumber(value: Double(value) / 1_000_000_000)).map { $0 + "B" } ?? "\(value)"
        } else if value >= 1_000_000 {
            return f.string(from: NSNumber(value: Double(value) / 1_000_000)).map { $0 + "M" } ?? "\(value)"
        } else if value >= 1_000 {
            return f.string(from: NSNumber(value: Double(value) / 1_000)).map { $0 + "K" } ?? "\(value)"
        }
        return f.string(from: n) ?? "\(value)"
    }

    static func full(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    static func clockWithDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    /// 秒级窗口时长 humanize
    static func windowLength(seconds: Int) -> String {
        if seconds >= 86_400, seconds % 86_400 == 0 {
            let days = seconds / 86_400
            return days == 1 ? "24 小时" : "\(days) 天"
        }
        if seconds >= 3_600, seconds % 3_600 == 0 {
            return "\(seconds / 3_600) 小时"
        }
        if seconds >= 60, seconds % 60 == 0 {
            return "\(seconds / 60) 分钟"
        }
        return "\(seconds) 秒"
    }

    /// 剩余倒计时
    static func countdown(until unixSeconds: Int?, now: Date) -> String {
        guard let ts = unixSeconds else { return "—" }
        let remain = Date(timeIntervalSince1970: TimeInterval(ts)).timeIntervalSince(now)
        if remain <= 0 { return "即将重置" }
        let total = Int(remain)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if days > 0 { return String(format: "%d天 %02d:%02d:%02d", days, hours, minutes, seconds) }
        if hours > 0 { return String(format: "%02d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func percentColor(_ percent: Int?) -> NSColor {
        guard let p = percent else { return .systemGray }
        if p >= 90 { return .systemRed }
        if p >= 70 { return .systemOrange }
        return .systemGreen
    }
}
