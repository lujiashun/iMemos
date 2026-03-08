import SwiftUI
import Models
import ServiceUtils
import MemosV1Service

@MainActor
public struct ResetPasswordView: View {
    @State private var host = ""
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isPhoneVerified = false
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var errorMessage: String?
    @State private var showLoadingToast = false
    @State private var showSuccessToast = false
    @Environment(\.dismiss) private var dismiss

#if DEBUG
    @AppStorage("allowInsecureTLS") private var allowInsecureTLS = false
#endif
    
    public init(host: String) {
        _host = State(initialValue: host)
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Text("重置密码")
                .font(.title2)
                .padding(.bottom, 10)
            
            // 手机号输入
            VStack(alignment: .leading, spacing: 8) {
                Text("手机号")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("请输入手机号", text: $phoneNumber)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.phonePad)
                        .disabled(isPhoneVerified)
                    
                    Button {
                        Task {
                            await sendVerificationCode()
                        }
                    } label: {
                        if isSendingCode {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else if countdown > 0 {
                            Text("\(countdown)s")
                        } else {
                            Text(isPhoneVerified ? "已验证" : "发送验证码")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(phoneNumber.isEmpty || isSendingCode || countdown > 0 || isPhoneVerified)
                }
            }
            
            // 验证码输入
            VStack(alignment: .leading, spacing: 8) {
                Text("验证码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("请输入验证码", text: $verificationCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .disabled(isPhoneVerified)
                    
                    Button {
                        Task {
                            await verifyCode()
                        }
                    } label: {
                        Text(isPhoneVerified ? "已验证" : "验证")
                    }
                    .buttonStyle(.bordered)
                    .disabled(verificationCode.isEmpty || isPhoneVerified)
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // 新密码输入
            VStack(alignment: .leading, spacing: 8) {
                Text("新密码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("请输入新密码", text: $newPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            // 确认密码输入
            VStack(alignment: .leading, spacing: 8) {
                Text("确认密码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("请再次输入新密码", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
            
            Button {
                Task {
                    await resetPassword()
                }
            } label: {
                Text("重置密码")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
            .disabled(!isFormValid)
        }
        .padding()
        .overlay {
            if showLoadingToast {
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding(16)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .shadow(radius: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .alert("密码重置成功", isPresented: $showSuccessToast) {
            Button("确定") {
                dismiss()
            }
        } message: {
            Text("请使用新密码登录")
        }
        .navigationTitle("重置密码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .frame(minWidth: 44, minHeight: 44)
            }
        }
    }
    
    private var isFormValid: Bool {
        !newPassword.isEmpty &&
        newPassword == confirmPassword &&
        !phoneNumber.isEmpty &&
        isPhoneVerified
    }
    
    private func sendVerificationCode() async {
        do {
            isSendingCode = true
            let service = createService()
            let success = try await service.sendVerificationCode(
                phoneNumber: phoneNumber,
                purpose: .RESET_PASSWORD
            )
            if success {
                startCountdown()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingCode = false
    }
    
    private func startCountdown() {
        countdown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            countdown -= 1
            if countdown <= 0 {
                timer.invalidate()
            }
        }
    }
    
    private func verifyCode() async {
        do {
            showLoadingToast = true
            let service = createService()
            let valid = try await service.verifyPhone(
                phoneNumber: phoneNumber,
                purpose: .RESET_PASSWORD,
                authToken: verificationCode
            )
            if valid {
                isPhoneVerified = true
            } else {
                errorMessage = "验证码无效"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        showLoadingToast = false
    }
    
    private func resetPassword() async {
        do {
            showLoadingToast = true
            errorMessage = nil
            
            guard newPassword == confirmPassword else {
                errorMessage = "两次输入的密码不一致"
                showLoadingToast = false
                return
            }
            
            let service = createService()
            try await service.resetPassword(
                phoneNumber: phoneNumber,
                verificationCode: verificationCode,
                newPassword: newPassword
            )
            showSuccessToast = true
        } catch {
            errorMessage = error.localizedDescription
        }
        showLoadingToast = false
    }
    
    private func createService() -> MemosV1Service {
        var hostAddress = host.trimmingCharacters(in: .whitespaces)
        if !hostAddress.contains("//") {
            hostAddress = "https://" + hostAddress
        }
        if hostAddress.last == "/" {
            hostAddress.removeLast()
        }
        let hostURL = URL(string: hostAddress)!
        
#if DEBUG
        return MemosV1Service(hostURL: hostURL, username: nil, password: nil, userId: nil, allowInsecureTLS: allowInsecureTLS)
#else
        return MemosV1Service(hostURL: hostURL, username: nil, password: nil, userId: nil)
#endif
    }
}
