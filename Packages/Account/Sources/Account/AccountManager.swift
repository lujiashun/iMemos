//
//  AccountManager.swift
//  
//
//  Created by Mudkip on 2023/11/12.
//

import Foundation
import SwiftUI
import Models
import Factory

@Observable public final class AccountManager: @unchecked Sendable {
    @ObservationIgnored private var currentAccountKeyStore: UserDefaults = {
        if !AppInfo.groupContainerIdentifier.isEmpty, let ud = UserDefaults(suiteName: AppInfo.groupContainerIdentifier) {
            return ud
        }
        return UserDefaults.standard
    }()

    @ObservationIgnored private var currentAccountKey: String {
        get { currentAccountKeyStore.string(forKey: "currentAccountKey") ?? "" }
        set { currentAccountKeyStore.set(newValue, forKey: "currentAccountKey") }
    }
    @ObservationIgnored public private(set) var currentService: RemoteService?
    
    public var mustCurrentService: RemoteService {
        get throws {
            guard let service = currentService else { throw MoeMemosError.notLogin }
            return service
        }
    }
    
    public private(set) var accounts: [Account]
    public internal(set) var currentAccount: Account? {
        didSet {
            currentAccountKey = currentAccount?.key ?? ""
            currentService = currentAccount?.remoteService()
        }
    }
    
    public init() {
        accounts = Account.retriveAll()
        if !currentAccountKey.isEmpty, let currentAccount = accounts.first(where: { $0.key == currentAccountKey }) {
            self.currentAccount = currentAccount
        } else {
            self.currentAccount = accounts.last
        }
    }
    
    internal func add(account: Account) throws {
        try account.save()
        accounts = Account.retriveAll()
        currentAccount = account
    }
    
    internal func delete(account: Account) {
        print("AccountManager: Deleting account: \(account.key)")
        accounts.removeAll { $0.key == account.key }
        account.delete()
        if currentAccount?.key == account.key {
            print("AccountManager: Current account is being deleted, resetting...")
            currentAccount = accounts.last
            print("AccountManager: New current account is \(currentAccount?.key ?? "nil")")
        }
    }
}

public extension Container {
    var accountManager: Factory<AccountManager> {
        self { AccountManager() }.shared
    }
}

extension AccountManager {
    internal func update(account: Account) throws {
        try account.save()
        accounts = Account.retriveAll()
        if currentAccount?.key == account.key {
            currentAccount = account
        }
    }
}
