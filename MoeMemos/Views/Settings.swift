//
//  Settings.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/5.
//

import SwiftUI
import Models
import Account
import Env

struct Settings: View {
    @Environment(AppInfo.self) var appInfo: AppInfo
    @Environment(AccountViewModel.self) var accountViewModel
    @Environment(AccountManager.self) private var accountManager
    @Environment(AppPath.self) private var appPath
    @State private var showingSignOutConfirm = false

    var body: some View {
        @Bindable var accountViewModel = accountViewModel
        List {
            Section {
                if let key = accountManager.currentAccount?.key {
                    NavigationLink(value: Route.memosAccount(key)) {
                        Label("账号与密码", systemImage: "key")
                    }
                } else {
                    Button {
                        appPath.presentedSheet = .addAccount
                    } label: {
                        Label("账号与密码", systemImage: "key")
                    }
                }
            }
            
            Section {
                Link(destination: appInfo.website) {
                    Label("settings.website", systemImage: "globe")
                }
                Link(destination: appInfo.privacy) {
                    Label("settings.privacy", systemImage: "lock")
                }
                Link(destination: URL(string: "https://memos.littledaemon.dev/ios-acknowledgements")!) {
                    Label("settings.acknowledgements", systemImage: "info.bubble")

                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirm = true
                    } label: {
                        Label("settings.sign-out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.red)
                    }
                    .confirmationDialog("settings.sign-out", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                        Button(role: .destructive) {
                            Task { @MainActor in
                                guard let account = accountManager.currentAccount else { return }
                                do {
                                    try await accountViewModel.logout(account: account)
                                } catch {
                                    print(error)
                                }
                                appPath.presentedSheet = nil
                                appPath.presentedSheet = .addAccount
                            }
                        } label: {
                            Text("settings.sign-out")
                        }
                        } message: {
                            Text("settings.sign-out.confirm")
                    }
                }
                Link(destination: URL(string: "https://github.com/mudkipme/MoeMemos/issues")!) {
                    Label("settings.report", systemImage: "smallcircle.filled.circle")
                }
            } header: {
                Text("settings.about")
            } footer: {
                Text(appInfo.registration)
            }
        }
        .navigationTitle("settings")
    }
}
