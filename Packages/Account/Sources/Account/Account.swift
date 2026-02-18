//
//  Account.swift
//  
//
//  Created by Mudkip on 2023/11/12.
//

import Foundation
import Models
import KeychainSwift
import MemosV0Service
import MemosV1Service

public extension Account {
    private static var keychain: KeychainSwift {
        let keychain = KeychainSwift()
        if !AppInfo.keychainAccessGroupName.isEmpty {
            keychain.accessGroup = AppInfo.keychainAccessGroupName
        }
        return keychain
    }
    
    func save() throws {
        let data = try JSONEncoder().encode(self)
        Self.keychain.set(data, forKey: key, withAccess: .accessibleAfterFirstUnlock)
    }
    
    func delete() {
        Self.keychain.delete(key)
    }
    
    static func retriveAll() -> [Account] {
        let keychain = Self.keychain
        let decoder = JSONDecoder()
        let keys = keychain.allKeys
        var accounts = [Account]()
        
        for key in keys {
            if let data = keychain.getData(key), let account = try? decoder.decode(Account.self, from: data) {
                accounts.append(account)
            }
        }
        return accounts
    }
    
    func remoteService() -> RemoteService? {
        if case .memosV0(host: let host, id: _, username: let username, password: let password) = self, let hostURL = URL(string: host) {
            return MemosV0Service(hostURL: hostURL, username: username, password: password)
        }
        if case .memosV1(host: let host, id: let userId, username: let username, password: let password) = self, let hostURL = URL(string: host) {
            return MemosV1Service(hostURL: hostURL, username: username, password: password, userId: userId)
        }
        return nil
    }
    
    @MainActor
    func toUser() async throws -> User {
        if case .local = self {
            return User(accountKey: key, nickname: NSLocalizedString("account.local-user", comment: ""))
        }
        if let remoteService = remoteService() {
            let user = try await remoteService.getCurrentUser()
            user.accountKey = key
            return user
        }
        throw MoeMemosError.notLogin
    }
}
