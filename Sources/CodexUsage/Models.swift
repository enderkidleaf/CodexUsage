import Foundation

// MARK: - 后端 /wham/usage 接口模型（所有字段可选，向前兼容接口变化）

struct WhamUsage: Codable {
    let planType: String?
    let rateLimit: RateLimit?
    let modelUsage: [String: ModelAvailability]?
    let credits: Credits?
    let rateLimitResetCredits: ResetCredits?
    let rateLimitReachedType: RateLimitReachedType?
    let rateLimitUpsell: RateLimitUpsell?

    struct RateLimit: Codable {
        let allowed: Bool?
        let limitReached: Bool?
        let primaryWindow: RateWindow?
        let secondaryWindow: RateWindow?
    }

    struct RateWindow: Codable {
        let usedPercent: Int?
        let limitWindowSeconds: Int?
        let resetAfterSeconds: Int?
        let resetAt: Int?
    }

    struct ModelAvailability: Codable {
        let available: Bool?
        let availableAt: String?
        let creditsWouldEnable: Bool?
    }

    struct Credits: Codable {
        let hasCredits: Bool?
        let unlimited: Bool?
        let overageLimitReached: Bool?
        let balance: String?
    }

    struct ResetCredits: Codable {
        let availableCount: Int?
        let applicableAvailableCount: Int?
    }

    struct RateLimitReachedType: Codable {
        let type: String?
        let details: String?
    }

    struct RateLimitUpsell: Codable {
        let title: String?
        let description: String?
        let resetAt: Int?
    }
}

// MARK: - 本地会话 token 统计

struct TokenAggregate: Equatable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0
    var reasoningTokens: Int = 0
    var totalTokens: Int = 0
    var recordCount: Int = 0
}

// MARK: - 面板统一状态

enum UsageFetchError: LocalizedError {
    case authMissing
    case authInvalid
    case tokenExpired(Date?)
    case http(Int, String)
    case network(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .authMissing:
            return "未找到 Codex 登录信息（~/.codex/auth.json），请先安装并登录 Codex。"
        case .authInvalid:
            return "Codex 登录信息格式异常，请在 Codex 应用中重新登录。"
        case .tokenExpired:
            return "访问令牌已过期，请打开一次 Codex 应用完成自动续期。"
        case let .http(code, body):
            return "接口返回错误（HTTP \(code)）：\(body)"
        case let .network(msg):
            return "网络请求失败：\(msg)"
        case let .decoding(msg):
            return "响应解析失败：\(msg)"
        }
    }
}

enum AppRelativePath {
    static let codexHome = ".codex"
    static let authFile = ".codex/auth.json"
    static let sessionsDir = ".codex/sessions"
    static let usageURL = "https://chatgpt.com/backend-api/wham/usage"
    static let usageWebURL = "https://chatgpt.com/codex/settings/usage"
}
