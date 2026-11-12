import Library
import SwiftUI

/// 已登录的账户详情（commit 6 扩展为权益/流量展示）。
public struct AccountDetailView: View {
    @State private var email = ""

    public init() {}

    public var body: some View {
        FormView {
            Section {
                Text(email)
                    .font(.headline)
            }
        }
        .task {
            email = await VPMAuthService.displayEmail()
        }
    }
}
