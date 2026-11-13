import Library
import SwiftUI

/// 已登录的账户详情：权益与流量展示 + 购买入口 + 退出登录。
public struct AccountDetailView: View {
    @State private var email = ""
    @State private var entitlement: VPMENTitlement?
    @State private var traffic: VPMTrafficInfo?
    @State private var subscriptionImported = false
    @State private var isRefreshing = false

    public init() {}

    public var body: some View {
        FormView {
            Section {
                Text(email)
                    .font(.headline)
            }
            Section {
                if let entitlement = entitlement {
                    if entitlement.active, let product = entitlement.productName {
                        Text("Current plan: \(product) (\(entitlement.level))")
                        if let endAt = entitlement.endAt {
                            Text("Expires at: \(VPMDateUtil.display(endAt))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No active subscription")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Membership")
            }
            Section {
                if let traffic = traffic {
                    ProgressView(value: min(traffic.percent, 100), total: 100)
                    Text("Traffic used: \(VPMMoneyFormat.bytes(traffic.usedBytes)) / \(VPMMoneyFormat.bytes(traffic.baseQuotaBytes)) (\(Int(traffic.percent))%)")
                        .font(.footnote)
                    Text("Resets at: \(VPMDateUtil.display(traffic.resetAt))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Traffic")
            }
            Section {
                Text(subscriptionImported ? String(localized: "VPM subscription imported") : String(localized: "VPM subscription not imported yet"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    VPMStoreView()
                } label: {
                    Label("Buy a Plan", systemImage: "cart.fill")
                }
                Button {
                    Task { await refresh() }
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshing)
            } header: {
                Text("Subscription")
            }
            Section {
                Button(String(localized: "Sign Out"), role: .destructive) {
                    Task { await logout() }
                }
            }
        }
        .task {
            email = await VPMAuthService.displayEmail()
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vpmEntitlementChanged)) { _ in
            Task { await refresh() }
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            entitlement = try await VPMAPIClient.shared.request("/api/v1/entitlements/current") as VPMENTitlement
            let dashboard: VPMDashboardResponse = try await VPMAPIClient.shared.request("/api/v1/dashboard")
            traffic = dashboard.traffic
        } catch {
            // 会话过期等错误由 VPMAPIClient 广播处理
        }
        subscriptionImported = VPMDeviceService.shared.subscriptionImported
    }

    private func logout() async {
        await VPMAPIClient.shared.logout()
    }
}
