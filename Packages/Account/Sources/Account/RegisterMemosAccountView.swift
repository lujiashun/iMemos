import SwiftUI
import Models
import ServiceUtils
import MemosV1Service
import MemosV1Service

@MainActor
public struct RegisterMemosAccountView: View {
    @State private var host = ""
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var registerError: Error?
    @State private var showingErrorToast = false
    @State private var showLoadingToast = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack {
            Text("注册新账号")
                .font(.title2)
                .padding(.bottom, 20)
            TextField("服务器地址", text: $host)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $password)
                .textFieldStyle(.roundedBorder)
            TextField("邮箱（可选）", text: $email)
                .textFieldStyle(.roundedBorder)
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
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 20)
        }
        .padding()
        .toast(isPresenting: $showingErrorToast, alertType: .systemImage("xmark.circle", registerError?.localizedDescription))
        .toast(isPresenting: $showLoadingToast, alertType: .loading)
        .navigationTitle("注册账号")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func doRegister() async throws {
        print("[RegisterMemosAccountView] doRegister start host:\(host)")
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
        try await service.signUp(username: username, password: password, email: email.isEmpty ? nil : email)
        print("[RegisterMemosAccountView] doRegister finished")
    }
}
