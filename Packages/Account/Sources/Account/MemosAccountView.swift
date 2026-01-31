//
//  MemosAccountView.swift
//
//
//  Created by Mudkip on 2024/6/15.
//

import Foundation
import SwiftUI
import Models
import Env

public struct MemosAccountView: View {
    @State var user: User? = nil
    @State var version: MemosVersion? = nil
    @State private var isLoggingOut = false
    private let accountKey: String
    @Environment(AccountManager.self) private var accountManager
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(AppPath.self) private var appPath
    private var account: Account? { resolveAccount(from: accountKey) }
    @Environment(\.dismiss) private var dismiss
    
    public init(accountKey: String) {
        self.accountKey = accountKey
    }

    private func normalizeHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/$", with: "", options: .regularExpression)
    }

    private func parseAccountKey(_ key: String) -> (host: String, id: String)? {
        // Expected: "memos:<host>:<id>" where <host> can contain ':' (e.g. https://...).
        guard key.hasPrefix("memos:") else { return nil }
        guard let lastColon = key.lastIndex(of: ":") else { return nil }
        let id = String(key[key.index(after: lastColon)...])
        let hostStart = key.index(key.startIndex, offsetBy: "memos:".count)
        let host = String(key[hostStart..<lastColon])
        guard !host.isEmpty, !id.isEmpty else { return nil }
        return (host, id)
    }

    private func resolveAccount(from key: String) -> Account? {
        // Fast path
        if let exact = accountManager.accounts.first(where: { $0.key == key }) {
            return exact
        }

        // Robust match for cases like host having a trailing slash in the stored key.
        if key == "local" {
            return accountManager.accounts.first(where: { $0.key == "local" })
        }
        guard let parsed = parseAccountKey(key) else { return nil }
        let targetHost = normalizeHost(parsed.host)
        let targetId = parsed.id

        if let matched = accountManager.accounts.first(where: { account in
            switch account {
            case .memosV0(host: let host, id: let id, username: _, password: _):
                return normalizeHost(host) == targetHost && id == targetId
            case .memosV1(host: let host, id: let id, username: _, password: _):
                return normalizeHost(host) == targetHost && id == targetId
            case .local:
                return false
            }
        }) {
            return matched
        }

        // Last resort: if the user list got out of sync (stale accountKey), at least allow logging out
        // the currently selected account when the host matches.
        if let current = accountManager.currentAccount {
            switch current {
            case .memosV0(host: let host, id: _, username: _, password: _),
                 .memosV1(host: let host, id: _, username: _, password: _):
                if normalizeHost(host) == targetHost {
                    return current
                }
            case .local:
                break
            }
        }

        return nil
    }
    
    public var body: some View {
        List {
            if let user = user {
                VStack(alignment: .leading) {
                    if let avatarData = user.avatarData, let uiImage = UIImage(data: avatarData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    }
                    Text(user.nickname)
                        .font(.title3)
                    if let email = user.email, email != user.nickname && !email.isEmpty {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding([.top, .bottom], 10)
            }
            
            if let version = version?.version {
                Label(title: { Text("memos v\(version)").foregroundStyle(.secondary) }) {
                    Image(.memos)
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                }
            }
            
            if accountKey != accountManager.currentAccount?.key {
                Section {
                    Button {
                        Task {
                            do {
                                try await accountViewModel.switchTo(accountKey: accountKey)
                                dismiss()
                            } catch {
                                print(error)
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("account.switch-account")
                            Spacer()
                        }
                    }
                }
            }
            
            Section {
                Button(role: .destructive) {
                    Task { @MainActor in
                        print("MemosAccountView: Sign out button tapped")
                        guard let account = account else {
                            print("MemosAccountView: Sign out failed - account not found for key \(accountKey)")
                            print("MemosAccountView: known accounts: \(accountManager.accounts.map(\.key))")
                            return
                        }
                        isLoggingOut = true
                        defer { isLoggingOut = false }

                        do {
                            try await accountViewModel.logout(account: account)
                        } catch {
                            print(error)
                        }

                        // Force re-presentation even if the sheet is already shown.
                        appPath.presentedSheet = nil
                        appPath.presentedSheet = .addAccount
                    }
                } label: {
                    Group {
                        if isLoggingOut {
                            ProgressView()
                        } else {
                            Text("settings.sign-out")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(isLoggingOut)
            }
        }
        .navigationTitle("account.account-detail")
        .task {
            guard let account = account else { return }
            user = try? await account.remoteService()?.getCurrentUser()
        }
        .task {
            guard let account = account else { return }
            
            var hostURL: URL?
            switch account {
            case .memosV0(host: let host, id: _, username: _, password: _):
                hostURL = URL(string: host)
            case .memosV1(host: let host, id: _, username: _, password: _):
                hostURL = URL(string: host)
            case .local:
                return
            }
            guard let hostURL = hostURL else { return }
            version = try? await detectMemosVersion(hostURL: hostURL)
        }
    }
}
