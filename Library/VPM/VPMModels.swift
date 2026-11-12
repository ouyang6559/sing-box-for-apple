//
//  VPMModels.swift
//  sing-box-for-apple
//
//  VPM 门户 API 数据模型。字段名与 vpm backend 响应一一对应；
//  金额/流量类数值由服务端以十进制字符串返回，客户端按 String 解码。
//

import Foundation

// MARK: - Auth

public struct VPMLoginResponse: Decodable {
    public let accessToken: String
    public let expiresAt: String?
    public let customerId: String
}

public struct VPMRegisterResponse: Decodable {
    public let customerId: String
    public let accessToken: String
    public let expiresAt: String?
}

public struct VPMRefreshResponse: Decodable {
    public let accessToken: String
    public let expiresAt: String?
}

public struct VPMRequestResetResponse: Decodable {
    public let sent: Bool
    public let devCode: String?
}

public struct VPMResetPasswordResponse: Decodable {
    public let ok: Bool?
}

// MARK: - OAuth / Telegram

public struct VPMOAuthProvider: Decodable {
    public let provider: String
    public let enabled: Bool
}

public struct VPMOAuthProvidersResponse: Decodable {
    public let items: [VPMOAuthProvider]
}

public struct VPMOAuthStartResponse: Decodable {
    public let authUrl: String
    public let expiresAt: String?
}

public struct VPMTGLoginStartResponse: Decodable {
    public let code: String
    public let botUsername: String
    public let startUrl: String
    public let expiresAt: String?
}

public struct VPMTGLoginStatusResponse: Decodable {
    public let status: String // PENDING | UNBOUND | VERIFIED | EXPIRED
    public let accessToken: String?
    public let expiresAt: String?
    public let customerId: String?
    public let telegramName: String?
}

// MARK: - Commerce

public struct VPMProductListResponse: Decodable {
    public let items: [VPMProduct]
    public let currency: String?
}

public struct VPMProduct: Decodable {
    public let id: String
    public let code: String
    public let name: String
    public let level: String
    public let durationDays: Int
    public let cycleDays: Int
    public let quotaBytes: String
    public let deviceLimit: Int
    public let priceMinor: String
    public let currency: String
    public let provisional: Bool?
}

public struct VPMQuoteResponse: Decodable {
    public let quoteId: String
    public let productId: String
    public let productName: String
    public let totalMinor: String
    public let walletPartMinor: String
    public let externalPartMinor: String
    public let currency: String
    public let replacementRequired: Bool?
    public let expectedEntitlementVersion: Int?
    public let expiresAt: String
    public let autoRenew: Bool
}

public struct VPMOrder: Decodable {
    public let id: String
    public let status: String // PENDING | PAID | FULFILLED | CANCELLED | FAILED
    public let totalMinor: String?
}

public struct VPMPaymentAction: Decodable {
    public let type: String // QR_CODE | PAY_URL | ADDRESS
    public let provider: String
    public let qrData: String?
    public let payUrl: String?
    public let address: String?
    public let token: String?
    public let amount: String?
    public let network: String?
    public let expiresAt: String?
}

public struct VPMCheckoutResponse: Decodable {
    public let order: VPMOrder
    public let paymentAction: VPMPaymentAction?
}

public struct VPMPaymentEntry: Decodable {
    public let provider: String
    public let status: String
    public let currency: String
    public let transactionId: String?
    public let amountMinor: String?
    public let paidAt: String?
}

public struct VPMOrderStatusResponse: Decodable {
    public let id: String
    public let status: String
    public let totalMinor: String?
    public let payments: [VPMPaymentEntry]?
}

public struct VPMPaymentMethod: Decodable {
    public let id: String // alipay | wechat | usdt | usdc | mock | wallet
    public let kind: String // QR | CRYPTO
    public let token: String?
    public let network: String?
    public let enabled: Bool
}

public struct VPMPaymentMethodsResponse: Decodable {
    public let items: [VPMPaymentMethod]
}

// MARK: - Entitlement / Traffic

public struct VPMENTitlement: Decodable {
    public let level: String
    public let active: Bool
    public let quotaBytes: String?
    public let deviceLimit: Int?
    public let autoRenew: Bool?
    public let productName: String?
    public let startAt: String?
    public let endAt: String?
    public let cycleDays: Int?
}

public struct VPMTrafficInfo: Decodable {
    public let usedBytes: String
    public let baseQuotaBytes: String
    public let grantedBytes: String
    public let remainingBytes: String
    public let resetAt: String
    public let percent: Double
}

public struct VPMDashboardResponse: Decodable {
    public let traffic: VPMTrafficInfo
    public let serverTime: String?
}

// MARK: - Devices / Subscription

public struct VPMDevice: Decodable {
    public let id: String
    public let name: String
    public let platform: String
    public let status: String
    public let online: Bool?
    public let clientProfileId: String?
}

public struct VPMDeviceListResponse: Decodable {
    public let items: [VPMDevice]
}

public struct VPMDeviceCreateResponse: Decodable {
    public let id: String
    public let name: String
    public let platform: String
    public let status: String
}

public struct VPMDeviceSubscriptionResponse: Decodable {
    public let deviceId: String
    public let status: String
    public let subscriptionUrls: [String: String] // format -> url，format: clash | singbox | v2ray | wireguard
    public let nodeCount: Int
}
