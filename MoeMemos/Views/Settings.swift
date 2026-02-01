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
