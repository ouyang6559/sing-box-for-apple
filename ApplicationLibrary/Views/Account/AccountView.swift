import Library
import SwiftUI

/// 账户页根视图：未登录展示认证表单，已登录展示权益详情。
public struct AccountView: View {
    @State private var isLoggedIn = VPMAPIClient.shared.isLoggedIn

    public init() {}

    public var body: some View {
        Group {
            if isLoggedIn {
                AccountDetailView()
            } else {
                AuthView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .vpmLoginStateChanged)) { _ in
            isLoggedIn = VPMAPIClient.shared.isLoggedIn
        }
    }
}
