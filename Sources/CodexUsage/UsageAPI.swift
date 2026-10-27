import Foundation

/// 只读取 Codex 本机登录信息并调用只读用量接口。
/// 安全约束：绝不使用 refresh_token、绝不回写 ~/.codex 下的任何文件。
final class UsageAPI {

    private struct AuthFile: Codable {
        let authMode: String?
        let tokens: Tokens?
        struct Tokens: Codable {
            let accessToken: String?
            let accountId: String?
            let refreshToken: String?
        }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 20
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - 认证文件读取

    private func loadAuth() throws -> AuthFile {
        let url = homeDirectory.appendingPathComponent(AppRelativePath.authFile)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw UsageFetchError.authMissing
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AuthFile.self, from: data)
        } catch {
            throw UsageFetchError.authInvalid
        }
    }

    /// 解析 JWT payload 中的 exp（unix 秒）。不校验签名，仅用于本地判断过期时间。
    private func tokenExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var s = String(parts[1])
        let pad = (4 - s.count % 4) % 4
        s.append(contentsOf: String(repeating: "=", count: pad))
        guard let raw = Data(base64Encoded: s.replacingOccurrences(of: "-", with: "+")
                              .replacingOccurrences(of: "_", with: "/")),
              let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let exp = obj["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: - 拉取用量

    func fetchUsage() async throws -> WhamUsage {
        let auth = try loadAuth()
        guard let token = auth.tokens?.accessToken, !token.isEmpty,
              let accountId = auth.tokens?.accountId, !accountId.isEmpty else {
            throw UsageFetchError.authInvalid
        }

        if let exp = tokenExpiry(token), exp <= Date() {
            throw UsageFetchError.tokenExpired(exp)
        }

        guard let url = URL(string: AppRelativePath.usageURL) else {
            throw UsageFetchError.network("用量接口地址无效")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(accountId, forHTTPHeaderField: "chatgpt-account-id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("codex_cli_rs/0.164.0", forHTTPHeaderField: "User-Agent")
        req.setValue("https://chatgpt.com", forHTTPHeaderField: "Origin")
        req.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw UsageFetchError.network(error.localizedDescription)
        }

        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            if code == 401 || code == 403 {
                throw UsageFetchError.tokenExpired(self.tokenExpiry(token))
            }
            let snippet = String(data: data, encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(200) ?? ""
            throw UsageFetchError.http(code, String(snippet))
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(WhamUsage.self, from: data)
        } catch {
            throw UsageFetchError.decoding(error.localizedDescription)
        }
    }
}
