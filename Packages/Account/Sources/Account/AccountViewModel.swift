//
//  AccountViewModel.swift
//
//
//  Created by Mudkip on 2024/6/5.
//

import Foundation
import SwiftData
import Models
import Factory
import MemosV1Service
import MemosV0Service

enum AccountCredentialError: LocalizedError {
    case unsupported
    case oldPasswordMismatch

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return NSLocalizedString("account.password.unsupported", comment: "")
        case .oldPasswordMismatch:
            return NSLocalizedString("account.password.old.wrong", comment: "")
        }
    }
}

@Observable public final class AccountViewModel: @unchecked Sendable {
    @ObservationIgnored private var currentContext: ModelContext
    private var accountManager: AccountManager
    @ObservationIgnored private let userActor = UserModelActor()

    public init(currentContext: ModelContext, accountManager: AccountManager) {
        self.currentContext = currentContext
        self.accountManager = accountManager
        users = (try? currentContext.fetch(FetchDescriptor<User>())) ?? []
    }
    
    public private(set) var users: [User]
    public var currentUser: User? {
        if let account = self.accountManager.currentAccount {
            return users.first { $0.accountKey == account.key }
        }
        return nil
    }
    
    @MainActor
    public func reloadUsers() async throws {
        let savedUsers = try currentContext.fetch(FetchDescriptor<User>())
        var allUsers = [User]()
        for account in accountManager.accounts {
            if accountManager.currentAccount == account {
                guard let currentService = accountManager.currentService else { throw MoeMemosError.notLogin }
                let user = try await currentService.getCurrentUser()
                if let existingUser = savedUsers.first(where: { $0.accountKey == account.key }) {
                    existingUser.avatarData = user.avatarData
                    existingUser.nickname = user.nickname
                    existingUser.defaultVisibility = user.defaultVisibility
                    existingUser.email = user.email
                    existingUser.creationDate = user.creationDate
                    existingUser.remoteId = user.remoteId
                    allUsers.append(existingUser)
                } else {
                    // Canonicalize accountKey so it always matches Account.key.
                    user.accountKey = account.key
                    currentContext.insert(user)
                    allUsers.append(user)
                }
            } else if let user = savedUsers.first(where: { $0.accountKey == account.key }) {
                allUsers.append(user)
            } else if let user = try? await account.toUser() {
                allUsers.append(user)
                currentContext.insert(user)
            }
        }

        // Remove removed users
        savedUsers.filter { user in !accountManager.accounts.contains { $0.key == user.accountKey } }.forEach { user in
            currentContext.delete(user)
        }
        try currentContext.save()
        users = allUsers
    }
    
    @MainActor
    public func logout(account: Account) async throws {
        print("AccountViewModel: logout started for account \(account.key)")
        do {
            let wasCurrentAccount = accountManager.currentAccount?.key == account.key
            accountManager.delete(account: account)
            if wasCurrentAccount {
                accountManager.currentAccount = nil
            }
            try await reloadUsers()
            print("AccountViewModel: logout finished for account \(account.key)")
        } catch {
            print("AccountViewModel: logout failed with error: \(error)")
            throw error
        }
    }
    
    @MainActor
    func switchTo(accountKey: String) async throws {
        guard let account = accountManager.accounts.first(where: { $0.key == accountKey }) else { return }
        accountManager.currentAccount = account
        try await reloadUsers()
    }
    
    @MainActor
    func loginMemosV0(hostURL: URL, username: String, password: String) async throws {
        print("[AccountViewModel] loginMemosV0 start host:\(hostURL.absoluteString) username:\(username)")
        let client = MemosV0Service(hostURL: hostURL, username: username, password: password)
        let user = try await client.getCurrentUser()
        print("[AccountViewModel] loginMemosV0 fetched user remoteId:\(user.remoteId ?? "nil")")
        guard let id = user.remoteId else { throw MoeMemosError.unsupportedVersion }
        let account = Account.memosV0(host: hostURL.absoluteString, id: id, username: username, password: password)
        try await userActor.deleteUser(currentContext, accountKey: account.key)
        try accountManager.add(account: account)
        print("[AccountViewModel] loginMemosV0 success accountKey:\(account.key)")
        try await reloadUsers()
    }
    
    @MainActor
    func loginMemosV1(hostURL: URL, username: String, password: String) async throws {
        print("[AccountViewModel] loginMemosV1 start host:\(hostURL.absoluteString) username:\(username)")
        let client = MemosV1Service(hostURL: hostURL, username: username, password: password, userId: nil)
        let user = try await client.getCurrentUser()
        print("[AccountViewModel] loginMemosV1 fetched user remoteId:\(user.remoteId ?? "nil")")
        guard let id = user.remoteId else { throw MoeMemosError.unsupportedVersion }
        let account = Account.memosV1(host: hostURL.absoluteString, id: id, username: username, password: password)
        try await userActor.deleteUser(currentContext, accountKey: account.key)
        try accountManager.add(account: account)
        print("[AccountViewModel] loginMemosV1 success accountKey:\(account.key)")
        try await reloadUsers()
    }
}

public extension Container {
    var accountViewModel: Factory<AccountViewModel> {
        self { AccountViewModel(currentContext: self.appInfo().modelContext, accountManager: self.accountManager()) }.shared
    }
}

public extension AccountViewModel {
    @MainActor
    func updateNickname(to nickname: String) async throws {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MoeMemosError.invalidParams }

        guard let currentAccount = accountManager.currentAccount else { throw MoeMemosError.notLogin }
        switch currentAccount {
        case .local:
            if let user = currentUser {
                user.nickname = trimmed
                try currentContext.save()
            }
        case .memosV1:
            guard let v1 = accountManager.currentService as? MemosV1Service else { throw MoeMemosError.notLogin }
            _ = try await v1.updateDisplayName(trimmed)
        case .memosV0:
            throw MoeMemosError.unsupportedVersion
        }
        try await reloadUsers()
    }

    @MainActor
    func changePassword(oldPassword: String, newPassword: String) async throws {
        guard let currentAccount = accountManager.currentAccount else { throw MoeMemosError.notLogin }
        guard let v1 = accountManager.currentService as? MemosV1Service else { throw AccountCredentialError.unsupported }

        guard case let .memosV1(host: host, id: id, username: username, password: storedPassword) = currentAccount else {
            throw AccountCredentialError.unsupported
        }

        guard storedPassword == oldPassword else { throw AccountCredentialError.oldPasswordMismatch }
        let trimmed = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MoeMemosError.invalidParams }

        try await v1.updatePassword(trimmed)

        let updatedAccount = Account.memosV1(host: host, id: id, username: username, password: trimmed)
        try accountManager.update(account: updatedAccount)
        try await reloadUsers()
    }
}
