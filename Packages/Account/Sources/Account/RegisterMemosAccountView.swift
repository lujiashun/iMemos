import SwiftUI
import Models
import ServiceUtils
import MemosV1Service

@MainActor
public struct RegisterMemosAccountView: View {
    @State private var host = "memos.yingshun.xin"
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var registerError: Error?
    @State private var showingErrorToast = false
    @State private var showLoadingToast = false
    @Environment(\.dismiss) private var dismiss

#if DEBUG
    @AppStorage("allowInsecureTLS") private var allowInsecureTLS = false
#endif
    
    public init() {}
    
    public var body: some View {
        VStack {
            Text("注册新账号")
                .font(.title2)
                .padding(.bottom, 20)
            // Host is fixed to yingshun.xin
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
            TextField("邮箱（可选）", text: $email)
                .textFieldStyle(.roundedBorder)

#if DEBUG
            Toggle("允许不安全证书（仅调试）", isOn: $allowInsecureTLS)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
#endif
            Button {
                Task {
                    do {
                        print("[RegisterMemosAccountView] register button tapped host:\(host) username:\(username) email:\(email)")
                        showLoadingToast = true
                        try await doRegister()
                        print("[RegisterMemosAccountView] register succeeded host:\(host) username:\(username)")
                        registerError = nil
                        dismiss()
                    } catch {
                        print("[RegisterMemosAccountView] register failed host:\(host) username:\(username) error:\(error)")
                        registerError = error
                        showingErrorToast = true
                    }
                    showLoadingToast = false
                }
            } label: {
                Text("注册")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 20)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .toast(isPresenting: $showingErrorToast, alertType: .systemImage("xmark.circle", registerError.map(userFacingErrorMessage)))
        .toast(isPresenting: $showLoadingToast, alertType: .loading)
        .navigationTitle("注册账号")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
    
    private func doRegister() async throws {
        print("[RegisterMemosAccountView] doRegister start host:\(host)")

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            throw MoeMemosError.invalidParams
        }

        var hostAddress = host.trimmingCharacters(in: .whitespaces)
        if !hostAddress.contains("//") {
            hostAddress = "https://" + hostAddress
        }
        if hostAddress.last == "/" {
            hostAddress.removeLast()
        }
        guard let hostURL = URL(string: hostAddress) else { throw MoeMemosError.invalidParams }
        print("[RegisterMemosAccountView] doRegister resolved hostURL:\(hostURL.absoluteString)")
        let service = MemosV1Service(hostURL: hostURL, username: nil, password: nil, userId: nil)
        try await service.signUp(username: trimmedUsername, password: trimmedPassword, email: trimmedEmail.isEmpty ? nil : trimmedEmail)
        print("[RegisterMemosAccountView] doRegister finished")
    }
}
