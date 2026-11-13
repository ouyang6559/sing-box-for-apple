import Foundation

/// 套餐购买：商品/支付方式/报价/下单/订单轮询。
public enum VPMStoreService {
    public static func listProducts() async throws -> VPMProductListResponse {
        let resp: VPMProductListResponse = try await VPMAPIClient.shared.request("/api/v1/products")
        return resp
    }

    public static func listPaymentMethods() async throws -> VPMPaymentMethodsResponse {
        let resp: VPMPaymentMethodsResponse = try await VPMAPIClient.shared.request("/api/v1/payment-methods")
        return resp
    }

    public static func quote(productId: String, autoRenew: Bool) async throws -> VPMQuoteResponse {
        let resp: VPMQuoteResponse = try await VPMAPIClient.shared.request("/api/v1/orders:quote",
                                              method: "POST",
                                              body: ["productId": productId, "autoRenew": autoRenew])
        return resp
    }

    public static func checkout(quoteId: String, paymentMethod: String) async throws -> VPMCheckoutResponse {
        let resp: VPMCheckoutResponse = try await VPMAPIClient.shared.request("/api/v1/orders:checkout",
                                              method: "POST",
                                              body: ["quoteId": quoteId, "paymentMethod": paymentMethod, "replaceAcknowledgement": ""],
                                              idempotencyKey: UUID().uuidString)
        return resp
    }

    public static func orderStatus(orderId: String) async throws -> VPMOrderStatusResponse {
        let resp: VPMOrderStatusResponse = try await VPMAPIClient.shared.request("/api/v1/orders/\(orderId)")
        return resp
    }

    /// 每 5 秒轮询订单直到终态或超时；返回是否支付成功。
    public static func pollOrder(orderId: String,
                                 interval: UInt64 = 5_000_000_000,
                                 timeout: UInt64 = 30 * 60 * UInt64(1_000_000_000),
                                 onStatus: ((String) -> Void)? = nil) async -> Bool {
        var elapsed: UInt64 = 0
        while elapsed < timeout {
            do {
                let resp = try await orderStatus(orderId: orderId)
                onStatus?(resp.status)
                if resp.status == "FULFILLED" || resp.status == "PAID" {
                    return true
                }
                if resp.status == "FAILED" || resp.status == "CANCELLED" {
                    return false
                }
            } catch {
                // 网络抖动不终止轮询
            }
            try? await Task.sleep(nanoseconds: interval)
            elapsed += interval
        }
        return false
    }
}

/// 金额/字节展示工具。
public enum VPMMoneyFormat {
    public static func display(minor: String, currency: String) -> String {
        guard let value = Double(minor) else { return minor }
        if currency == "CNY" {
            return String(format: "¥%.2f", value / 100)
        }
        return "\(minor) \(currency)"
    }

    public static func bytes(_ value: String) -> String {
        guard let count = Double(value) else { return value }
        let units: [String] = ["B", "KB", "MB", "GB", "TB"]
        var number = count
        var index = 0
        while number >= 1024 && index < units.count - 1 {
            number /= 1024
            index += 1
        }
        return index == 0 ? String(format: "%.0f%@", number, units[index]) : String(format: "%.2f%@", number, units[index])
    }
}

/// RFC3339 时间展示。
public enum VPMDateUtil {
    public static func display(_ rfc3339: String?) -> String {
        guard let rfc3339 = rfc3339, let date = formatter.date(from: rfc3339) else { return "—" }
        return displayFormatter.string(from: date)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
