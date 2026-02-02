//
//  AddMemosAccountView.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import SwiftUI
// ...existing code...
import Models
import MemosV0Service
import DesignSystem

@MainActor
public struct AddMemosAccountView: View {
    @State private var host = "demo.usememos.com"
    @State private var username = ""
    @State private var password = ""
    @State private var showingRegister = false
        @Environment(\.dismiss) private var dismiss
    @Environment(AppInfo.self) private var appInfo: AppInfo
    @Environment(AccountViewModel.self) private var accountViewModel
    @State private var loginError: Error?
    @State private var showingErrorToast = false
    @State private var showLoadingToast = false
    @State private var agreedToTerms = false
    public init() {}
    
    public var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 0) {
                (
                    Text("login.hint.line1.part1")
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                    + Text("login.hint.line1.part2")
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                )
                .font(.headline)
                .scaleEffect(2, anchor: .leading)
                .padding(.bottom, 40)

                Text("login.hint.line2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .scaleEffect(1.3, anchor: .leading)
                    .padding(.bottom, 8)
                Text("login.hint.line3")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .scaleEffect(1.3, anchor: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(.bottom, 20)
            .offset(y: -120)
            
            // Host is fixed to demo.usememos.com
            
            TextField("login.user", text: $username)
                .textFieldStyle(.roundedBorder)
            SecureField("login.passwd", text: $password)
                .textFieldStyle(.roundedBorder)
            
            Button {
                Task {
                    do {
                        print("[AddMemosAccountView] login button tapped host:\(host) username:\(username)")
                        showLoadingToast = true
                        try await doLogin()
                        print("[AddMemosAccountView] login succeeded for host:\(host) username:\(username)")
                        loginError = nil
                    } catch {
                        print("[AddMemosAccountView] login failed for host:\(host) username:\(username) error:\(error)")
                        loginError = error
                        showingErrorToast = true
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            showingErrorToast = false
                        }
                    }
                    showLoadingToast = false
                }
            } label: {
                Text("login.sign-in")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 20)
            .disabled(!agreedToTerms)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    agreedToTerms.toggle()
                } label: {
                    Image(systemName: agreedToTerms ? "checkmark.square.fill" : "square")
                        .foregroundStyle(agreedToTerms ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)

                Group {
                    Text("login.agree.prefix")
                    Link("login.agree.terms", destination: appInfo.terms)
                    Text("login.agree.conjunction")
                    Link("login.agree.privacy", destination: appInfo.privacy)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)

            Button {
                showingRegister = true
            } label: {
                Text("没有账号？注册新账号")
                    .font(.footnote)
                    .foregroundColor(.blue)
            }
            .padding(.top, 8)
        }
        .padding()
        .sheet(isPresented: $showingRegister) {
            NavigationStack {
                RegisterMemosAccountView()
            }
        }
        .toast(isPresenting: $showingErrorToast, duration: 1.5, alertType: .systemImage("xmark.circle", loginError?.localizedDescription))
        .toast(isPresenting: $showLoadingToast, alertType: .loading)
        .navigationTitle("account.add-memos-account")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func doLogin() async throws {
        print("[AddMemosAccountView] doLogin start host:\(host)")
        
        var hostAddress = host.trimmingCharacters(in: .whitespaces)
        if !hostAddress.contains("//") {
            hostAddress = "https://" + hostAddress
        }
        if hostAddress.last == "/" {
            hostAddress.removeLast()
        }
        
        guard let hostURL = URL(string: hostAddress) else { throw MoeMemosError.invalidParams }
        let server = try await detectMemosVersion(hostURL: hostURL)

        let username = username.trimmingCharacters(in: .whitespaces)
        let password = password.trimmingCharacters(in: .whitespaces)
        if username.isEmpty || password.isEmpty {
            throw MoeMemosError.invalidParams
        }

        switch server {
        case .v1(version: _):
            try await accountViewModel.loginMemosV1(hostURL: hostURL, username: username, password: password)
        case .v0(version: _):
            try await accountViewModel.loginMemosV0(hostURL: hostURL, username: username, password: password)
        }
        print("[AddMemosAccountView] doLogin finished, dismissing")
        dismiss()
    }
}
