import Library
import SwiftUI

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

enum AuthMode: String, CaseIterable, Identifiable {
    case login, register, reset

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .login:
            return String(localized: "Sign In")
        case .register:
            return String(localized: "Sign Up")
        case .reset:
            return String(localized: "Reset Password")
        }
    }
}

@MainActor
class AuthViewModel: BaseViewModel {
    @Published var mode: AuthMode = .login
    @Published var email = ""
    @Published var password = ""
    @Published var inviteCode = ""
    @Published var resetToken = ""
    @Published var newPassword = ""
    @Published var statusText = ""

    #if !os(tvOS)
        @Published var providers: [VPMOAuthProvider] = []
        @Published var telegramPrompt: String?
        var telegramCode: String?
        var telegramStartURL: String?
        var telegramPollTask: Task<Void, Never>?
    #endif

    func loadProviders() async {
        #if !os(tvOS)
            providers = await VPMOAuthService.shared.fetchProviders()
        #endif
    }

    func startOAuth(provider: String) async {
        #if !os(tvOS)
            statusText = String(localized: "Waiting for provider…")
            do {
                try await VPMOAuthService.shared.startOAuth(provider: provider)
            } catch let error as VPMError {
                statusText = error.displayMessage
            } catch {
                statusText = error.localizedDescription
            }
        #endif
    }

    func startTelegramLogin() async {
        #if !os(tvOS)
            do {
                let resp = try await VPMOAuthService.shared.telegramLoginStart()
                telegramCode = resp.code
                telegramStartURL = resp.startUrl
                telegramPrompt = String(localized: "Send /start \(resp.code) to @\(resp.botUsername) in Telegram, then wait.")
                telegramPollTask = Task { await pollTelegramLogin(code: resp.code) }
            } catch let error as VPMError {
                statusText = error.displayMessage
            } catch {
                statusText = error.localizedDescription
            }
        #endif
    }

    func openTelegramBot() {
        #if !os(tvOS)
            guard let startURL = telegramStartURL, let url = URL(string: startURL) else { return }
            #if os(macOS)
                NSWorkspace.shared.open(url)
            #elseif canImport(UIKit)
                UIApplication.shared.open(url)
            #endif
        #endif
    }

    func cancelTelegramLogin() {
        #if !os(tvOS)
            telegramPollTask?.cancel()
            telegramPollTask = nil
            telegramPrompt = nil
            telegramCode = nil
        #endif
    }

    #if !os(tvOS)
        private func pollTelegramLogin(code: String) async {
            while !Task.isCancelled {
                do {
                    let resp = try await VPMOAuthService.shared.telegramLoginStatus(code: code)
                    switch resp.status {
                    case "VERIFIED":
                        await VPMAuthService.storeSession(accessToken: resp.accessToken, email: nil)
                        telegramPrompt = nil
                        statusText = ""
                        return
                    case "UNBOUND":
                        statusText = String(localized: "This Telegram account is not linked yet. Bind it on the portal first.")
                        telegramPrompt = nil
                        return
                    case "EXPIRED":
                        statusText = String(localized: "Login code expired, please retry.")
                        telegramPrompt = nil
                        return
                    default:
                        break // PENDING
                    }
                } catch let error as VPMError {
                    statusText = error.displayMessage
                    telegramPrompt = nil
                    return
                } catch {
                    statusText = error.localizedDescription
                    telegramPrompt = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    #endif

    func submit() async {
        statusText = ""
        do {
            switch mode {
            case .login:
                guard !email.isEmpty, !password.isEmpty else {
                    statusText = String(localized: "Email and password are required.")
                    return
                }
                _ = try await VPMAuthService.login(email: email, password: password)
                statusText = String(localized: "Signed in.")
            case .register:
                guard !email.isEmpty, password.count >= 8 else {
                    statusText = String(localized: "Email and a password of at least 8 characters are required.")
                    return
                }
                _ = try await VPMAuthService.register(email: email, password: password, inviteCode: inviteCode)
                statusText = String(localized: "Account created and signed in.")
            case .reset:
                guard !email.isEmpty, !resetToken.isEmpty, newPassword.count >= 8 else {
                    statusText = String(localized: "Email, reset code and a new password of at least 8 characters are required.")
                    return
                }
                _ = try await VPMAuthService.resetPassword(email: email, token: resetToken, newPassword: newPassword)
                statusText = String(localized: "Password reset. Please sign in.")
                mode = .login
            }
        } catch let error as VPMError {
            statusText = error.displayMessage
        } catch {
            statusText = error.localizedDescription
        }
    }

    func sendResetCode() async {
        guard !email.isEmpty else {
            statusText = String(localized: "Email is required.")
            return
        }
        do {
            let resp = try await VPMAuthService.requestPasswordReset(email: email)
            if let devCode = resp.devCode {
                resetToken = devCode
                statusText = String(localized: "Dev mode: code auto-filled below.")
            } else {
                statusText = String(localized: "Reset code sent to your email.")
            }
        } catch let error as VPMError {
            statusText = error.displayMessage
        } catch {
            statusText = error.localizedDescription
        }
    }
}

/// 未登录时的认证视图：登录/注册/找回三段表单（邮箱为默认登录方式）。
public struct AuthView: View {
    @State private var viewModel = AuthViewModel()

    public init() {}

    public var body: some View {
        FormView {
            Section {
                Picker("", selection: $viewModel.mode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                #if os(tvOS)
                    .disabled(true)
                #endif
                TextField(String(localized: "Email"), text: $viewModel.email)
                    .autocorrectionDisabled()
                    .vpmEmailKeyboard()
                SecureField(String(localized: "Password (min 8 chars)"), text: $viewModel.password)
                if viewModel.mode == .register {
                    TextField(String(localized: "Invite code (optional)"), text: $viewModel.inviteCode)
                }
                if viewModel.mode == .reset {
                    HStack {
                        TextField(String(localized: "Reset code"), text: $viewModel.resetToken)
                        Button(String(localized: "Send Code")) {
                            Task { await viewModel.sendResetCode() }
                        }
                    }
                    SecureField(String(localized: "New password"), text: $viewModel.newPassword)
                }
                Button(actionLabel) {
                    Task { await viewModel.submit() }
                }
                .disabled(viewModel.isLoading)
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                if !viewModel.statusText.isEmpty {
                    Text(viewModel.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            #if !os(tvOS)
                Section {
                    ForEach(viewModel.providers.filter { $0.enabled && $0.provider != "telegram" }, id: \.provider) { provider in
                        Button(providerTitle(provider.provider)) {
                            Task { await viewModel.startOAuth(provider: provider.provider) }
                        }
                    }
                    Button(String(localized: "Telegram")) {
                        Task { await viewModel.startTelegramLogin() }
                    }
                } header: {
                    Text("Or continue with")
                }
                if let prompt = viewModel.telegramPrompt {
                    Section {
                        Text(prompt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Open Telegram")) {
                            viewModel.openTelegramBot()
                        }
                        Button(String(localized: "Cancel"), role: .cancel) {
                            viewModel.cancelTelegramLogin()
                        }
                    }
                }
            #endif
        }
        .task {
            await viewModel.loadProviders()
        }
        .alert($viewModel.alert)
    }

    private func providerTitle(_ provider: String) -> String {
        switch provider {
        case "google":
            return String(localized: "Continue with Google")
        case "x":
            return String(localized: "Continue with X")
        default:
            return provider
        }
    }

    private var actionLabel: String {
        switch viewModel.mode {
        case .login:
            return String(localized: "Sign In")
        case .register:
            return String(localized: "Sign Up")
        case .reset:
            return String(localized: "Reset")
        }
    }
}

extension View {
    /// iOS 专属键盘修饰符的平台门控（macOS/tvOS 无 keyboardType）。
    @ViewBuilder
    func vpmEmailKeyboard() -> some View {
        #if os(iOS)
            self.keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
        #else
            self
        #endif
    }
}
