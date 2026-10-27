import Foundation

// 数据层冒烟测试：直接验证远程用量接口与本地 token 扫描，不经过 UI
let sem = DispatchSemaphore(value: 0)
Task.detached {
    do {
        let u = try await UsageAPI().fetchUsage()
        print("[OK] plan = \(u.planType ?? "?")")
        print("[OK] limitReached = \(u.rateLimit?.limitReached.map(String.init) ?? "?")")
        print("[OK] primary percent = \(u.rateLimit?.primaryWindow?.usedPercent.map(String.init) ?? "?")")
        print("[OK] primary resetAt = \(u.rateLimit?.primaryWindow?.resetAt.map(String.init) ?? "?")")
        print("[OK] secondary percent = \(u.rateLimit?.secondaryWindow?.usedPercent.map(String.init) ?? "?")")
        print("[OK] credits balance = \(u.credits?.balance ?? "?")")
        print("[OK] reset credits = \(u.rateLimitResetCredits?.availableCount.map(String.init) ?? "?")")
    } catch {
        print("[FAIL] fetch: \(error)")
    }
    let agg = await TokenUsageScanner().scanToday()
    print("[OK] today totalTokens = \(agg.totalTokens), records = \(agg.recordCount)")
    print("[OK] today input = \(agg.inputTokens), cached = \(agg.cachedInputTokens), output = \(agg.outputTokens)")
    sem.signal()
}
sem.wait()
