import AuthenticationServices
import Foundation
import os

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// 第三方授权登录（Google/X/Telegram）。
/// OAuth: 系统 Web 认证会话或浏览器 + sing-box://vpm-auth 深链回调。
/// tvOS 无浏览器授权场景，仅保留邮箱登录。
public final class VPMOAuthService {
    public static let shared = VPMOAuthService()

    private let logger = Logger(category: "VPMOAuthService")

    #if !os(tvOS)
        /// Web 认证会话的强引用容器。
        private var sessionBox: AnyObject?
    #endif

    private static let deepLink = "sing-box://vpm-auth"

    // MARK: - Providers

    public func fetchProviders() async -> [VPMOAuthProvider] {
        do {
            let resp: VPMOAuthProvidersResponse = try await VPMAPIClient.shared.request("/api/v1/auth/oauth/providers", requiresAuth: false)
            return resp.items
        } catch {
            logger.error("VPM fetch oauth providers failed: \(error)")
            return []
        }
    }

    // MARK: - OAuth (Google / X)

    public func startOAuth(provider: String) async throws {
        let start: VPMOAuthStartResponse = try await VPMAPIClient.shared.request("/api/v1/auth/oauth/\(provider):start",
                                                                                 method: "POST",
                                                                                 body: ["deepLink": VPMOAuthService.deepLink],
                                                                                 requiresAuth: false)
        try await presentAuthURL(urlString: start.authUrl)
    }

    private func presentAuthURL(urlString: String) async throws {
        guard let url = URL(string: urlString) else {
            throw VPMError.invalidBaseURL
        }
        #if os(tvOS)
            throw VPMError.network("OAuth is not available on tvOS")
        #else
            guard let anchor = presentationAnchor() else {
                throw VPMError.network("no presentation anchor")
            }
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "sing-box") { [weak self] callbackURL, _ in
                guard let self = self else { return }
                if let callbackURL = callbackURL {
                    self.handleAuthCallbackURL(callbackURL)
                }
            }
            session.presentationContextProvider = PresentationAnchorProvider(anchor: anchor)
            let box = VPMWebAuthSessionBox()
            box.session = session
            sessionBox = box
            if session.start() {
                return
            }
            // Web 认证会话启动失败时降级为系统浏览器 + 深链回调。
            #if os(macOS)
                NSWorkspace.shared.open(url)
            #elseif canImport(UIKit)
                try await UIApplication.shared.open(url)
            #endif
        #endif
    }

    #if !os(tvOS)
        private func presentationAnchor() -> ASPresentationAnchor? {
            #if os(iOS)
                return UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first { $0.isKeyWindow }
            #elseif os(macOS)
                return NSApp.mainWindow ?? ASPresentationAnchor()
            #else
                return nil
            #endif
        }
    #endif

    /// sing-box://vpm-auth?ticket=... 统一入口（Web 认证会话与深链共用）。
    public func handleAuthCallbackURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            logger.error("VPM oauth callback error: \(error)")
            NotificationCenter.default.post(name: .vpmOAuthFailed, object: nil)
            return
        }
        guard let ticket = components.queryItems?.first(where: { $0.name == "ticket" })?.value else { return }
        Task {
            do {
                let resp = try await exchange(ticket: ticket)
                await VPMAuthService.storeSession(accessToken: resp.accessToken, email: nil)
            } catch {
                logger.error("VPM oauth exchange failed: \(error)")
                NotificationCenter.default.post(name: .vpmOAuthFailed, object: nil)
            }
        }
    }

    public func exchange(ticket: String) async throws -> VPMLoginResponse {
        let resp: VPMLoginResponse = try await VPMAPIClient.shared.request("/api/v1/auth/oauth:exchange",
                                              method: "POST",
                                              body: ["ticket": ticket],
                                              requiresAuth: false)
        return resp
    }

    // MARK: - Telegram

    public func telegramLoginStart() async throws -> VPMTGLoginStartResponse {
        try await VPMAPIClient.shared.request("/api/v1/auth/telegram:login:start",
                                              method: "POST",
                                              requiresAuth: false)
    }

    public func telegramLoginStatus(code: String) async throws -> VPMTGLoginStatusResponse {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? code
        let resp: VPMTGLoginStatusResponse = try await VPMAPIClient.shared.request("/api/v1/auth/telegram:login:status?code=\(encoded)",
                                                     requiresAuth: false)
        return resp
    }
}

#if !os(tvOS)
    /// ASWebAuthenticationSession 需要强引用；用容器绕过存储属性的可用性标注限制。
    @available(iOS 13.0, macOS 10.15, *)
    private final class VPMWebAuthSessionBox {
        var session: ASWebAuthenticationSession?
    }

    private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
        private let anchor: ASPresentationAnchor

        init(anchor: ASPresentationAnchor) {
            self.anchor = anchor
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }
#endif
