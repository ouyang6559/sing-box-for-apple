import Foundation

/// 邮箱注册/登录/找回密码与会话状态管理（OAuth/TG 共用 storeSession）。
public enum VPMAuthService {
    public static func displayEmail() async -> String {
        await SharedPreferences.vpmDisplayEmail.get()
    }
    public static func login(email: String, password: String) async throws -> VPMLoginResponse {
        let resp: VPMLoginResponse = try await VPMAPIClient.shared.request("/api/v1/auth/login",
                                                         method: "POST",
                                                         body: ["email": email, "password": password, "rememberMe": true],
                                                         requiresAuth: false)
        await storeSession(accessToken: resp.accessToken, email: email)
        return resp
    }

    public static func register(email: String, password: String, inviteCode: String) async throws -> VPMRegisterResponse {
        let resp: VPMRegisterResponse = try await VPMAPIClient.shared.request("/api/v1/auth/register",
                                                         method: "POST",
                                                         body: ["email": email,
                                                                "password": password,
                                                                "verificationToken": "",
                                                                "inviteCode": inviteCode],
                                                         requiresAuth: false)
        await storeSession(accessToken: resp.accessToken, email: email)
        return resp
    }

    public static func requestPasswordReset(email: String) async throws -> VPMRequestResetResponse {
        try await VPMAPIClient.shared.request("/api/v1/auth/password:request-reset",
                                              method: "POST",
                                              body: ["email": email],
                                              requiresAuth: false)
    }

    public static func resetPassword(email: String, token: String, newPassword: String) async throws -> VPMResetPasswordResponse {
        try await VPMAPIClient.shared.request("/api/v1/auth/password:reset",
                                              method: "POST",
                                              body: ["email": email, "token": token, "newPassword": newPassword],
                                              requiresAuth: false)
    }

    /// 任意登录方式拿到 accessToken 后统一落地并广播登录态变化。
    public static func storeSession(accessToken: String?, email: String?) async {
        VPMAPIClient.shared.updateAccessToken(accessToken)
        if let email = email {
            await SharedPreferences.vpmDisplayEmail.set(email)
        }
        await MainActor.run {
            NotificationCenter.default.post(name: .vpmLoginStateChanged, object: nil)
        }
    }
}
