import Combine
import Foundation
import Libbox
import Library
import os

#if canImport(UIKit)
    import UIKit
#endif

/// 登录模式下的设备注册与 sing-box 订阅导入：
/// 登录成功 → 查询设备（空则自动创建）→ 获取 format=singbox 订阅链接 →
/// 去重后创建远程 Profile（开启自动更新）。订阅链接含 token，禁止落日志。
/// 导入完成后广播 vpmProfilesChanged：各平台 Delegate 负责重配自动更新任务，
/// ExtensionEnvironments 负责刷新 profile 列表。
@MainActor
public final class VPMDeviceService: ObservableObject {
    public static let shared = VPMDeviceService()

    private static let subscriptionProfileName = "VPM Subscription"
    private static let singboxFormat = "singbox"
    private static let autoUpdateInterval: Int32 = 48 * 3600

    private let logger = Logger(category: "VPMDeviceService")
    @Published public var subscriptionImported = false
    private var importing = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: .vpmLoginStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.refreshImportState()
                    if VPMAPIClient.shared.isLoggedIn {
                        await self.ensureSubscriptionAfterLogin()
                    }
                }
            }
            .store(in: &cancellables)
        Task {
            await refreshImportState()
        }
    }

    public func refreshImportState() async {
        do {
            let profiles = try await ProfileManager.list()
            subscriptionImported = profiles.contains { $0.name == VPMDeviceService.subscriptionProfileName }
        } catch {
            logger.error("VPM refresh import state failed: \(error)")
        }
    }

    /// 登录态变化后调用：已登录则确保设备存在并导入订阅。
    public func ensureSubscriptionAfterLogin() async {
        guard await SharedPreferences.vpmLoginModeEnabled.get(), VPMAPIClient.shared.isLoggedIn, !importing else { return }
        importing = true
        defer { importing = false }
        do {
            if let url = try await ensureDeviceAndSubscription() {
                try await importSubscription(url: url)
            }
        } catch {
            logger.error("VPM ensure subscription failed: \(error)")
        }
    }

    public func ensureDeviceAndSubscription() async throws -> String? {
        let list: VPMDeviceListResponse = try await VPMAPIClient.shared.request("/api/v1/devices")
        let active = list.items.filter { $0.status != "DELETED" }
        let deviceId: String
        if let existing = active.first {
            deviceId = existing.id
        } else {
            deviceId = try await createDevice().id
        }
        return try await fetchSubscription(deviceId: deviceId)
    }

    private func createDevice() async throws -> VPMDeviceCreateResponse {
        let body: [String: Any] = ["name": deviceName(), "platform": platformName()]
        let resp: VPMDeviceCreateResponse = try await VPMAPIClient.shared.request("/api/v1/devices", method: "POST", body: body)
        return resp
    }

    private func fetchSubscription(deviceId: String) async throws -> String? {
        let resp: VPMDeviceSubscriptionResponse = try await VPMAPIClient.shared.request("/api/v1/devices/\(deviceId)/subscription")
        return resp.subscriptionUrls[VPMDeviceService.singboxFormat]
    }

    private func deviceName() -> String {
        #if os(macOS)
            return Host.current().localizedName ?? "sing-box"
        #else
            return UIDevice.current.name
        #endif
    }

    private func platformName() -> String {
        #if os(macOS)
            return "macos"
        #elseif os(tvOS)
            return "tvos"
        #else
            return "ios"
        #endif
    }

    /// 去重导入：同名 Profile 更新订阅 URL，否则新建远程 Profile 并立即拉取。
    public func importSubscription(url: String) async throws {
        let profiles = try await ProfileManager.list()
        if let existing = profiles.first(where: { $0.name == VPMDeviceService.subscriptionProfileName }) {
            if existing.remoteURL == url {
                await refreshImportState()
                return
            }
            existing.remoteURL = url
            existing.autoUpdate = true
            existing.autoUpdateInterval = VPMDeviceService.autoUpdateInterval
            try await existing.updateRemoteProfile()
            try await ProfileManager.update(existing)
        } else {
            let nextProfileID = try await ProfileManager.nextID()
            let remoteContent = try await HTTPClient.getStringAsync(url)
            try await BlockingIO.run {
                var error: NSError?
                LibboxCheckConfig(remoteContent, &error)
                if let error {
                    throw error
                }
            }
            let profileConfigDirectory = FilePath.sharedDirectory.appendingPathComponent("configs", isDirectory: true)
            let profileConfig = profileConfigDirectory.appendingPathComponent("config_\(nextProfileID).json")
            try await BlockingIO.run {
                try FileManager.default.createDirectory(at: profileConfigDirectory, withIntermediateDirectories: true)
                try remoteContent.write(to: profileConfig, atomically: true, encoding: .utf8)
            }
            let profile = Profile(
                name: VPMDeviceService.subscriptionProfileName,
                type: .remote,
                path: "configs/config_\(nextProfileID).json",
                remoteURL: url,
                autoUpdate: true,
                autoUpdateInterval: VPMDeviceService.autoUpdateInterval,
                lastUpdated: .now
            )
            try await ProfileManager.create(profile)
        }
        await refreshImportState()
        NotificationCenter.default.post(name: .vpmProfilesChanged, object: nil)
    }
}
