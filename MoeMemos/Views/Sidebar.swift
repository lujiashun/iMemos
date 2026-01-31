//
//  Sidebar.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import SwiftUI
import Account
import Env
import Models

struct Sidebar: View {
    @Environment(MemosViewModel.self) private var memosViewModel: MemosViewModel
    @Environment(AccountManager.self) private var accountManager: AccountManager
    @Environment(AccountViewModel.self) private var userState: AccountViewModel
    @Binding var selection: Route?
    var onSidebarItemSelect: (() -> Void)? = nil

    private var isPadOrVision: Bool {
        UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision
    }

    private func SidebarLink<V: View>(value: Route, @ViewBuilder label: () -> V) -> some View {
        Group {
            if isPadOrVision {
                NavigationLink(value: value, label: label)
            } else {
                Button(action: {
                    selection = value
                    onSidebarItemSelect?()
                }) {
                    label()
                }
                .foregroundStyle(.primary)
            }
        }
    }

    var body: some View {
        let list = List(selection: isPadOrVision ? $selection : nil) {
            Stats()
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .listRowBackground(EmptyView())
            
            Section {
                SidebarLink(value: Route.memos) {
                    Label("memo.memos", systemImage: "rectangle.grid.1x2")
                }
                SidebarLink(value: Route.explore) {
                    Label("explore", systemImage: "house")
                }
                SidebarLink(value: Route.resources) {
                    Label("resources", systemImage: "photo.on.rectangle")
                }
                SidebarLink(value: Route.archived) {
                    Label("memo.archived", systemImage: "archivebox")
                }
            } header: {
                Text("moe-memos")
            }
            
            Section {
                OutlineGroup(memosViewModel.nestedTags, children: \.children) { item in
                    SidebarLink(value: Route.tag(Tag(name: item.fullName))) {
                        Label(item.name, systemImage: "number")
                    }
                }
            } header: {
                Text("tags")
            }
        }
        .safeAreaInset(edge: .top) {
            if !isPadOrVision {
                HStack {
                    Spacer()
                    Button(action: {
                        selection = .settings
                        onSidebarItemSelect?()
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 10) // Small top padding inside the safe area container
                }
                .frame(height: 50)
                .background(Color(UIColor.secondarySystemBackground))
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            if isPadOrVision {
                Button(action: {
                    selection = .settings
                }) {
                    Image(systemName: "ellipsis")
                }
            } else {
                Button(action: { selection = .settings }) {
                    Image(systemName: "ellipsis")
                }
            }
        }

            Group {
                if isPadOrVision {
                    list
                        .navigationTitle(userState.currentUser?.nickname ?? NSLocalizedString("memo.memos", comment: "Memos"))
                } else {
                    list
                }
            }
    }
}
