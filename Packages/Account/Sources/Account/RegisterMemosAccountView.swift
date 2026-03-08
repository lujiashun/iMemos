import SwiftUI
import Models
import ServiceUtils
import MemosV1Service

@MainActor
public struct RegisterMemosAccountView: View {
    @State private var host = "memos.yingshun.xin"
    @State private var username = ""
    @State private var password = ""
    @State private var phoneNumber = ""
    @State private var verificationCode = ""
    @State private var isPhoneVerified = false
    @State private var isSendingCode = false
    @State private var countdown = 0
    @State private var registerError: Error?
    @State private var showingErrorToast = false
    @State private var showLoadingToast = false
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 16) {
            Text("注册新账号")
                .font(.title2)
                .padding(.bottom, 10)
            
            // 用户名输入
            VStack(alignment: .leading, spacing: 8) {
                Text("用户名")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("请输入用户名", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            
            // 密码输入
            VStack(alignment: .leading, spacing: 8) {
                Text("密码")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField("请输入密码", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            
            Divider()
                .padding(.vertical, 8)
            
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
            
            Button {
                Task {
                    do {
                        print("[RegisterMemosAccountView] register button tapped host:\(host) username:\(username) phoneNumber:\(phoneNumber)")
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
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
            .disabled(!isFormValid)
        }
        .padding()
        .overlay(alignment: .top) {
            if showingErrorToast, let err = registerError {
                Text(userFacingErrorMessage(err))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onTapGesture { showingErrorToast = false }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
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
        .navigationTitle("注册账号")
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
        !username.isEmpty &&
        !password.isEmpty &&
        !phoneNumber.isEmpty &&
        isPhoneVerified
    }
    
    private func sendVerificationCode() async {
        do {
            isSendingCode = true
            print("[RegisterMemosAccountView] sendVerificationCode start phoneNumber:\(phoneNumber)")
            let service = createService()
            print("[RegisterMemosAccountView] service created")
            let success = try await service.sendVerificationCode(
                phoneNumber: phoneNumber,
                purpose: .REGISTER
            )
            print("[RegisterMemosAccountView] sendVerificationCode result: \(success)")
            if success {
                startCountdown()
            }
        } catch {
            print("[RegisterMemosAccountView] sendVerificationCode error: \(error)")
            registerError = error
            showingErrorToast = true
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
                purpose: .REGISTER,
                authToken: verificationCode
            )
            if valid {
                isPhoneVerified = true
            } else {
                registerError = MoeMemosError.invalidParams
                showingErrorToast = true
            }
        } catch {
            registerError = error
            showingErrorToast = true
        }
        showLoadingToast = false
    }
    
    private func doRegister() async throws {
        print("[RegisterMemosAccountView] doRegister start host:\(host)")

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = verificationCode.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty, !trimmedPhone.isEmpty, !trimmedCode.isEmpty else {
            throw MoeMemosError.invalidParams
        }

        let service = createService()
        try await service.signUpWithSMS(
            username: trimmedUsername,
            password: trimmedPassword,
            phoneNumber: trimmedPhone,
            verificationCode: trimmedCode
        )
        print("[RegisterMemosAccountView] doRegister finished")
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
