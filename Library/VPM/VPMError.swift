import Foundation

/// VPM API 统一错误：api 分支对应服务端 {code,reason,message} 结构。
public enum VPMError: Error {
    case invalidBaseURL
    case network(String)
    case api(code: Int, reason: String, message: String)
    case decoding(String)

    public var displayMessage: String {
        switch self {
        case .invalidBaseURL:
            return String(localized: "Invalid server address")
        case let .network(message):
            return String(localized: "Network error: \(message)")
        case let .api(_, reason, message):
            if let localized = VPMErrorReasonMap.localizedReason(for: reason) {
                return localized
            }
            return message.isEmpty ? String(localized: "Unknown error") : message
        case let .decoding(message):
            return String(localized: "Invalid server response: \(message)")
        }
    }

    public static func from(data: Data?, statusCode: Int) -> VPMError {
        if let data = data {
            struct APIErrorBody: Decodable {
                let code: Int?
                let reason: String?
                let message: String?
            }
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data), let reason = body.reason {
                return .api(code: body.code ?? statusCode, reason: reason, message: body.message ?? "")
            }
        }
        return .api(code: statusCode, reason: "UNKNOWN", message: "")
    }
}

/// vpm 错误 reason → 本地化文案；未收录的 reason 返回 nil（回退服务器 message）。
enum VPMErrorReasonMap {
    static func localizedReason(for reason: String) -> String? {
        let key = "vpm.reason.\(reason)"
        let localized = String(localized: String.LocalizationValue(key))
        return localized == key ? nil : localized
    }
}

public extension Notification.Name {
    static let vpmSessionExpired = Notification.Name("io.nekohasekai.sfa.vpm.sessionExpired")
    static let vpmLoginStateChanged = Notification.Name("io.nekohasekai.sfa.vpm.loginStateChanged")
    static let vpmEntitlementChanged = Notification.Name("io.nekohasekai.sfa.vpm.entitlementChanged")
    static let vpmOAuthFailed = Notification.Name("io.nekohasekai.sfa.vpm.oauthFailed")
}
