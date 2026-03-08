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
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var errorMessage: String?
    @State private var showLoadingToast = false
    @State private var showSuccessToast = false
    @Environment(\.dismiss) private var dismiss
    
    public init(host: String) {
        _host = State(initialValue: host)
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            TextField("手机号", text: $phoneNumber)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.phonePad)
            
            HStack {
                TextField("验证码", text: $verificationCode)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                
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
                        Text("发送验证码")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(phoneNumber.isEmpty || isSendingCode || countdown > 0)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            SecureField("新密码", text: $newPassword)
                .textFieldStyle(.roundedBorder)
            
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
        !phoneNumber.isEmpty &&
        !verificationCode.isEmpty
    }
    
    private func sendVerificationCode() async {
        do {
            isSendingCode = true
            let service = createService()
            let success = try await service.sendVerificationCode(
                phoneNumber: phoneNumber,
                purpose: .FORGOT_PASSWORD
            )
            if success {
                startCountdown()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingCode = false
    }
    
    @State private var countdownTimer: Timer?
    
    private func startCountdown() {
        countdown = 60
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                countdown -= 1
                if countdown <= 0 {
                    countdownTimer?.invalidate()
                    countdownTimer = nil
                }
            }
        }
    }
    
    private func resetPassword() async {
        do {
            showLoadingToast = true
            errorMessage = nil
            
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
        return MemosV1Service(hostURL: hostURL, username: nil, password: nil, userId: nil)
    }
}
