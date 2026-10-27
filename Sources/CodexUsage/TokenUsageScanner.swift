import Foundation

/// 扫描 ~/.codex/sessions 下的 rollout 会话文件，统计今日 token 消耗。
/// 数据源：每行一个 JSON 事件，token_usage_record 事件内含本次响应 usage；
/// 按 response_id 去重，避免同一响应在多个 rollout（fork / 子代理）中重复计数。
final class TokenUsageScanner {

    private let fileManager = FileManager.default
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func scanToday() async -> TokenAggregate {
        await Task.detached(priority: .utility) { [self] in
            self.scanSync()
        }.value
    }

    private func scanSync() -> TokenAggregate {
        let sessions = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(AppRelativePath.sessionsDir)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: sessions.path, isDirectory: &isDir), isDir.boolValue else {
            return TokenAggregate()
        }

        // rollout 文件按 UTC 日期分目录，而“今日”按本地时区判定；
        // 本地一天的起止时刻最多跨越两个 UTC 日期，因此只需扫描 1~2 个日期目录。
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)?.addingTimeInterval(-1) ?? Date()
        let dayDirs: Set<URL> = [utcDayDirs(for: dayStart, base: sessions),
                                 utcDayDirs(for: dayEnd, base: sessions)]

        var urls: [URL] = []
        let existing = dayDirs.filter { fileManager.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            for dir in existing { urls.append(contentsOf: contents(of: dir)) }
        } else {
            // 目录结构缺失时兜底全量扫描
            urls = contents(of: sessions)
        }

        var seenResponses = Set<String>()
        var agg = TokenAggregate()

        for url in urls where url.lastPathComponent.hasSuffix(".jsonl") || url.lastPathComponent.hasSuffix(".jsonl.zst") {
            guard let text = readRollout(url) else { continue }
            accumulate(text: text, calendar: cal, seen: &seenResponses, aggregate: &agg)
        }
        return agg
    }

    /// 把某个本地时刻换算成 UTC 日期对应的 rollout 目录（sessions/YYYY/MM/dd）
    private func utcDayDirs(for date: Date, base: URL) -> URL {
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        let c = utcCal.dateComponents([.year, .month, .day], from: date)
        return base
            .appendingPathComponent(String(format: "%04d", c.year ?? 0))
            .appendingPathComponent(String(format: "%02d", c.month ?? 0))
            .appendingPathComponent(String(format: "%02d", c.day ?? 0))
    }

    private func contents(of dir: URL) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let items = try? fileManager.contentsOfDirectory(at: dir,
                                                               includingPropertiesForKeys: nil,
                                                               options: opts) else {
            // 兜底递归
            if let enumr = fileManager.enumerator(at: dir,
                                                  includingPropertiesForKeys: nil,
                                                  options: opts) {
                return enumr.compactMap { $0 as? URL }
            }
            return []
        }
        // 当天目录本身就是平铺文件；若未来出现子目录则递归补齐
        var out: [URL] = []
        for item in items {
            var subDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &subDir), subDir.boolValue {
                out.append(contentsOf: contents(of: item))
            } else {
                out.append(item)
            }
        }
        return out
    }

    private func readRollout(_ url: URL) -> String? {
        if url.pathExtension == "zst" {
            guard let zstd = Self.locateZstd() else { return nil }
            let proc = Process()
            proc.executableURL = zstd
            proc.arguments = ["-dc", "-q", url.path]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            do {
                try proc.run()
            } catch {
                return nil
            }
            // 历史 rollout 可能较大，限上限 200MB 保护内存
            let raw = pipe.fileHandleForReading.readData(ofLength: 200_000_000)
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            return String(data: raw, encoding: .utf8)
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// 查找本机 zstd 命令行工具（Homebrew 等）。找不到时调用方跳过压缩文件，
    /// 当天 rollout 通常为明文 jsonl，今日统计不受影响。
    private static let zstdURL: URL? = {
        let candidates = [
            "/opt/homebrew/bin/zstd",
            "/usr/local/bin/zstd",
            "/usr/bin/zstd"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["zstd"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let p = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !p.isEmpty && FileManager.default.isExecutableFile(atPath: p) {
                return URL(fileURLWithPath: p)
            }
        } catch {}
        return nil
    }()

    private static func locateZstd() -> URL? { zstdURL }

    private func accumulate(text: String,
                            calendar: Calendar,
                            seen: inout Set<String>,
                            aggregate: inout TokenAggregate) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.contains("token_usage_record") else { continue }
            guard let data = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "token_usage_record",
                  let payload = obj["payload"] as? [String: Any] else { continue }

            if let ts = obj["timestamp"] as? String,
               let date = self.parseDate(ts),
               !calendar.isDateInToday(date) {
                continue
            }

            if let rid = payload["response_id"] as? String {
                if seen.contains(rid) { continue }
                seen.insert(rid)
            }

            guard let usage = payload["usage"] as? [String: Any] else { continue }
            let input = usage["input_tokens"] as? Int ?? 0
            let cached = usage["cached_input_tokens"] as? Int ?? 0
            let output = usage["output_tokens"] as? Int ?? 0
            let reasoning = usage["reasoning_output_tokens"] as? Int ?? 0
            let total = usage["total_tokens"] as? Int ?? 0

            aggregate.inputTokens += input
            aggregate.cachedInputTokens += cached
            aggregate.outputTokens += output
            aggregate.reasoningTokens += reasoning
            aggregate.totalTokens += total
            aggregate.recordCount += 1
        }
    }

    private func parseDate(_ s: String) -> Date? {
        if let d = isoFormatter.date(from: s) { return d }
        let fallback = ISO8601DateFormatter()
        return fallback.date(from: s)
    }
}
