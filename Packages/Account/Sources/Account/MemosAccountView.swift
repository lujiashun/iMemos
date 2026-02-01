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
    @State private var imageStorageUsedBytes: Int? = nil
    @State private var showingDeleteConfirm = false
    private let accountKey: String
    @Environment(AccountManager.self) private var accountManager
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(AppPath.self) private var appPath
    @Environment(AppInfo.self) private var appInfo
    private var account: Account? { resolveAccount(from: accountKey) }
    @Environment(\.dismiss) private var dismiss

    private var isCurrentAccount: Bool {
        accountKey == accountManager.currentAccount?.key
    }

    private var accountUsername: String? {
        guard let account else { return nil }
        switch account {
        case .memosV0(host: _, id: _, username: let username, password: _):
            return username
        case .memosV1(host: _, id: _, username: let username, password: _):
            return username
        case .local:
            return nil
        }
    }

    private var imageStorageText: String {
        guard let used = imageStorageUsedBytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let usedText = formatter.string(fromByteCount: Int64(used))
        let maxText = "—"
        return "\(usedText) / \(maxText)"
    }
    
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
            Section("account.section.basic-info") {
                if let user {
                    NavigationLink {
                        EditNicknameView(currentNickname: user.nickname)
                    } label: {
                        HStack {
                            Text("account.nickname")
                            Spacer()
                            Text(user.nickname)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .disabled(!isCurrentAccount)
                }

                HStack {
                    Text("account.storage")
                    Spacer()
                    Text(imageStorageText)
                        .foregroundStyle(.secondary)
                }
            }

            Section("account.section.account-settings") {
                if let username = accountUsername {
                    HStack {
                        Text("account.username")
                        Spacer()
                        Text(username)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                NavigationLink {
                    ChangePasswordView()
                } label: {
                    Text("account.change-password")
                }
                .disabled(!isCurrentAccount || accountUsername == nil)

                if !isCurrentAccount {
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
                        Text("account.switch-account")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }

            Section("account.section.service-info") {
                if let version = version?.version {
                    HStack {
                        Text("memos")
                        Spacer()
                        Text("v\(version)")
                            .foregroundStyle(.secondary)
                    }
                }

                Link(destination: appInfo.privacy) {
                    Text("settings.privacy")
                }
            }

            Section("account.section.delete-account") {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("account.delete-account-and-data")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(isLoggingOut)
                .confirmationDialog("account.delete-account-and-data", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                    Button(role: .destructive) {
                        Task { @MainActor in
                            print("MemosAccountView: Delete account button confirmed")
                            guard let account = account else {
                                print("MemosAccountView: Delete failed - account not found for key \(accountKey)")
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
                        Text("account.delete-account")
                    }
                } message: {
                    Text("account.delete-account.message")
                }
            }
        }
        .navigationTitle("account.account-detail")
        .task {
            guard let account = account else { return }
            user = try? await account.remoteService()?.getCurrentUser()
        }
        .task {
            guard let account = account else { return }
            if case .local = account {
                imageStorageUsedBytes = 0
                return
            }
            do {
                let resources = try await account.remoteService()?.listResources()
                let imageBytes = (resources ?? [])
                    .filter { $0.mimeType.hasPrefix("image/") }
                    .reduce(0) { $0 + $1.size }
                imageStorageUsedBytes = imageBytes
            } catch {
                imageStorageUsedBytes = nil
            }
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
