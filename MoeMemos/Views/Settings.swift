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
import Subscription
import MemosV1Service


struct Settings: View {
    @Environment(AppInfo.self) var appInfo: AppInfo
    @Environment(AccountViewModel.self) var accountViewModel
    @Environment(AccountManager.self) private var accountManager
    @Environment(AppPath.self) private var appPath
    @State private var showingSignOutConfirm = false
    @Environment(\.openURL) private var openURL

#if DEBUG
    @AppStorage("allowInsecureTLS") private var allowInsecureTLS = false
#endif

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (v?, b?):
            return "v\(v) (\(b))"
        case let (v?, nil):
            return "v\(v)"
        case let (nil, b?):
            return "(\(b))"
        default:
            return "-"
        }
    }

    var body: some View {
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
            
            if accountManager.currentService is MemosV1Service {
                Section {
                    Button {
                        print("[Settings] Subscription button tapped")
                        if let service = accountManager.currentService as? MemosV1Service {
                            appPath.subscriptionViewModel = SubscriptionFactory.createViewModel(service: service)
                            appPath.presentedSheet = .subscription
                        }
                    } label: {
                        Label {
                            Text("subscription.title")
                        } icon: {
                            Image(systemName: "crown")
                        }
                    }
                }
            }

            Section {
                Button {
                    openURL(appInfo.releases)
                } label: {
                    HStack {
                        Label("settings.check-update", systemImage: "arrow.down.circle")
                        Spacer()
                        Text(appVersionText)
                            .foregroundStyle(.secondary)
                    }
                }
            }

#if DEBUG
            Section {
                Toggle("允许不安全证书（仅调试）", isOn: $allowInsecureTLS)
            } header: {
                Text("Debug")
            } footer: {
                Text("开启后将跳过 TLS 证书校验，仅建议用于自签证书/mkcert 的开发环境。")
            }
#endif

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
        }
        .navigationTitle("settings")
    }
}
