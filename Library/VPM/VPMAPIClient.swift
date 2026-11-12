import Foundation
import os

/// VPM 门户 API 客户端：Bearer JWT + 401 单飞刷新重试 + Idempotency-Key。
/// 刷新令牌（vpm_refresh cookie）依赖 HTTPCookieStorage 持久化，随会话自动携带。
public final class VPMAPIClient {
    public static let shared = VPMAPIClient()

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let logger = Logger(category: "VPMAPIClient")

    private let lock = NSLock()
    private var isRefreshing = false
    private var refreshWaiters: [CheckedContinuation<Bool, Never>] = []

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        session = URLSession(configuration: configuration)
    }

    public func baseURL() async -> String {
        var base = await SharedPreferences.vpmAPIBaseURL.get().trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return base
    }

    public var accessToken: String? {
        VPMKeychain.get(account: VPMKeychain.Accounts.accessToken)
    }

    public var isLoggedIn: Bool {
        guard let token = accessToken else { return false }
        return !token.isEmpty
    }

    public func updateAccessToken(_ token: String?) {
        if let token = token, !token.isEmpty {
            VPMKeychain.set(value: token, account: VPMKeychain.Accounts.accessToken)
        } else {
            VPMKeychain.remove(account: VPMKeychain.Accounts.accessToken)
        }
    }

    /// 用户在设置中切换服务器地址时清空旧 cookie，避免刷新令牌串站。
    public func clearCookies() async {
        let base = await baseURL()
        guard let url = URL(string: base), let host = url.host else { return }
        for cookie in HTTPCookieStorage.shared.cookies(for: url) ?? [] where cookie.domain.contains(host) {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
    }

    public func logout() async {
        if let url = URL(string: await baseURL() + "/api/v1/auth/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            if let token = accessToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            _ = try? await session.data(for: request)
        }
        updateAccessToken(nil)
        await SharedPreferences.vpmDisplayEmail.set("")
        await clearCookies()
        await MainActor.run {
            NotificationCenter.default.post(name: .vpmLoginStateChanged, object: nil)
        }
    }

    public func request<T: Decodable>(_ path: String,
                                      method: String = "GET",
                                      body: [String: Any]? = nil,
                                      requiresAuth: Bool = true,
                                      idempotencyKey: String? = nil) async throws -> T {
        let data = try await perform(path, method: method, body: body, requiresAuth: requiresAuth, idempotencyKey: idempotencyKey, allowRefreshRetry: requiresAuth)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("VPM decode \(path, privacy: .public) failed: \(error)")
            throw VPMError.decoding(String(describing: error))
        }
    }

    private func perform(_ path: String,
                         method: String,
                         body: [String: Any]?,
                         requiresAuth: Bool,
                         idempotencyKey: String?,
                         allowRefreshRetry: Bool) async throws -> Data {
        guard let url = URL(string: await baseURL() + path) else {
            throw VPMError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if requiresAuth, let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey = idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw VPMError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw VPMError.network("invalid response")
        }
        let status = http.statusCode
        if (200..<300).contains(status) {
            return data
        }
        if status == 401, requiresAuth, allowRefreshRetry {
            logger.info("VPM access token expired, refreshing")
            let refreshed = await refreshSession()
            if refreshed {
                return try await perform(path, method: method, body: body, requiresAuth: requiresAuth, idempotencyKey: idempotencyKey, allowRefreshRetry: false)
            }
            await MainActor.run {
                NotificationCenter.default.post(name: .vpmSessionExpired, object: nil)
            }
        }
        throw VPMError.from(data: data, statusCode: status)
    }

    /// 并发的多个 401 只触发一次刷新。
    public func refreshSession() async -> Bool {
        lock.lock()
        if isRefreshing {
            return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                self.refreshWaiters.append(continuation)
                self.lock.unlock()
            }
        }
        isRefreshing = true
        lock.unlock()
        let refreshed = await doRefresh()
        lock.lock()
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        isRefreshing = false
        lock.unlock()
        for waiter in waiters {
            waiter.resume(returning: refreshed)
        }
        return refreshed
    }

    private func doRefresh() async -> Bool {
        guard let url = URL(string: await baseURL() + "/api/v1/auth/refresh") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["rememberMe": true])
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                let resp = try decoder.decode(VPMRefreshResponse.self, from: data)
                updateAccessToken(resp.accessToken)
                return true
            }
            return false
        } catch {
            logger.error("VPM refresh failed: \(error)")
            return false
        }
    }
}
