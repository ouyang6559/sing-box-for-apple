import CoreImage
import Library
import SwiftUI

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

@MainActor
class VPMStoreViewModel: BaseViewModel {
    @Published var products: [VPMProduct] = []
    @Published var currency = "CNY"
    @Published var methods: [VPMPaymentMethod] = []
    @Published var isLoadingProducts = false
    @Published var isPurchasing = false
    @Published var statusText = ""
    @Published var paymentAction: VPMPaymentAction?

    var pendingQuoteId: String?
    var pendingOrderId: String?
    var pollTask: Task<Void, Never>?

    func reload() async {
        isLoadingProducts = true
        statusText = ""
        paymentAction = nil
        defer { isLoadingProducts = false }
        do {
            let productResp = try await VPMStoreService.listProducts()
            products = productResp.items
            currency = productResp.currency ?? "CNY"
            let methodResp = try await VPMStoreService.listPaymentMethods()
            methods = methodResp.items.filter { $0.enabled }
        } catch let error as VPMError {
            statusText = error.displayMessage
        } catch {
            showError(error, action: "load products")
        }
    }

    func methodTitle(_ method: VPMPaymentMethod) -> String {
        switch method.id {
        case "alipay":
            return String(localized: "Alipay")
        case "wechat":
            return String(localized: "WeChat Pay")
        case "usdt":
            return method.network.map { "USDT (\($0))" } ?? "USDT"
        case "usdc":
            return method.network.map { "USDC (\($0))" } ?? "USDC"
        case "mock":
            return String(localized: "Mock (dev)")
        case "wallet":
            return String(localized: "Wallet balance")
        default:
            return method.id
        }
    }

    func buy(product: VPMProduct, method: VPMPaymentMethod) async {
        isPurchasing = true
        statusText = ""
        paymentAction = nil
        defer { isPurchasing = false }
        do {
            let quote = try await VPMStoreService.quote(productId: product.id, autoRenew: false)
            pendingQuoteId = quote.quoteId
            let checkout = try await VPMStoreService.checkout(quoteId: quote.quoteId, paymentMethod: method.id)
            pendingOrderId = checkout.order.id
            if checkout.order.status == "FULFILLED" {
                await onPaid()
                return
            }
            paymentAction = checkout.paymentAction
            guard let orderId = pendingOrderId else { return }
            let paid = await VPMStoreService.pollOrder(orderId: orderId)
            if paid {
                await onPaid()
            } else {
                statusText = String(localized: "Payment failed or timed out.")
            }
        } catch let error as VPMError {
            statusText = error.displayMessage
        } catch {
            showError(error, action: "checkout")
        }
    }

    func onPaid() async {
        statusText = String(localized: "Payment succeeded. Subscription activated.")
        NotificationCenter.default.post(name: .vpmEntitlementChanged, object: nil)
        await VPMDeviceService.shared.ensureSubscriptionAfterLogin()
        await reload()
    }

    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

public struct VPMStoreView: View {
    @State private var viewModel = VPMStoreViewModel()

    public init() {}

    public var body: some View {
        FormView {
            Section {
                ForEach(viewModel.products, id: \.id) { product in
                    ProductRow(product: product, currency: viewModel.currency) { method in
                        Task { await viewModel.buy(product: product, method: method) }
                    } methods: {
                        viewModel.methods
                    } methodTitle: { method in
                        viewModel.methodTitle(method)
                    }
                }
                if viewModel.products.isEmpty && !viewModel.isLoadingProducts {
                    Text("No plans available")
                        .foregroundStyle(.secondary)
                }
                if viewModel.isLoadingProducts {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } header: {
                Text("Plans & Payment")
            }
            if let action = viewModel.paymentAction {
                PaymentActionSection(action: action)
            }
            if !viewModel.statusText.isEmpty {
                Section {
                    Text(viewModel.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await viewModel.reload()
        }
        .onDisappear {
            viewModel.cancelPolling()
        }
        .alert($viewModel.alert)
    }
}

/// 商品行 + 支付方式菜单（从服务端 enabled 列表动态渲染）。
struct ProductRow: View {
    let product: VPMProduct
    let currency: String
    let onBuy: (VPMPaymentMethod) -> Void
    let methods: () -> [VPMPaymentMethod]
    let methodTitle: (VPMPaymentMethod) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(product.name)
                    .font(.headline)
                Spacer()
                Text(VPMMoneyFormat.display(minor: product.priceMinor, currency: currency))
                    .font(.body.monospacedDigit())
            }
            Text("\(product.durationDays) days · \(product.deviceLimit) devices")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(methods(), id: \.id) { method in
                    Button(methodTitle(method)) {
                        onBuy(method)
                    }
                }
            } label: {
                Label("Buy", systemImage: "cart.fill")
            }
            .disabled(methods().isEmpty)
        }
        .padding(.vertical, 2)
    }
}

/// 支付动作展示：QR_CODE（内置二维码）/ PAY_URL / ADDRESS（USDT/USDC）。
struct PaymentActionSection: View {
    let action: VPMPaymentAction

    var body: some View {
        Section {
            switch action.type {
            case "QR_CODE":
                if let qrData = action.qrData, let image = VPMQRCodeGenerator.image(for: qrData, size: 180) {
                    HStack {
                        Spacer()
                        image
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 180, height: 180)
                        Spacer()
                    }
                }
                if let payUrl = action.payUrl {
                    linkButtons(payUrl)
                } else if let qrData = action.qrData {
                    copyButton(qrData, label: String(localized: "Copy Link"))
                }
            case "PAY_URL":
                if let payUrl = action.payUrl {
                    linkButtons(payUrl)
                }
            default:
                if let address = action.address {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(action.token ?? "") (\(action.network ?? ""))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(address)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        if let amount = action.amount {
                            Text(String(localized: "Amount: \(amount) \(action.token ?? "")"))
                                .font(.footnote)
                        }
                    }
                    copyButton(address, label: String(localized: "Copy Address"))
                }
            }
            Text("Waiting for payment confirmation…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func linkButtons(_ url: String) -> some View {
        Button(String(localized: "Open in Browser")) {
            if let url = URL(string: url) {
                #if os(macOS)
                    NSWorkspace.shared.open(url)
                #elseif canImport(UIKit)
                    UIApplication.shared.open(url)
                #endif
            }
        }
        copyButton(url, label: String(localized: "Copy Link"))
    }

    private func copyButton(_ text: String, label: String) -> some View {
        Button(label) {
            #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            #elseif canImport(UIKit)
                UIPasteboard.general.string = text
            #endif
        }
    }
}

/// CIQRCodeGenerator 封装。
enum VPMQRCodeGenerator {
    static func image(for content: String, size: CGFloat) -> Image? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = max(size / output.extent.width, 1)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(macOS)
            return Image(nsImage: NSImage(cgImage: cgImage, size: NSSize(width: size, height: size)))
        #else
            return Image(uiImage: UIImage(cgImage: cgImage))
        #endif
    }
}
