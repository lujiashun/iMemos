//
//  Route.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/10/30.
//

import SwiftUI
import Models
import Env
import Account
import Factory

struct SidebarToggleAction: @unchecked Sendable {
    let perform: () -> Void

    init(_ perform: @escaping () -> Void = {}) {
        self.perform = perform
    }
}

struct NavigationSelectAction: @unchecked Sendable {
    let perform: (Route) -> Void

    init(_ perform: @escaping (Route) -> Void = { _ in }) {
        self.perform = perform
    }
}

private struct SidebarToggleKey: EnvironmentKey {
    fileprivate static let defaultValue = SidebarToggleAction()
}

private struct NavigationSelectKey: EnvironmentKey {
    fileprivate static let defaultValue = NavigationSelectAction()
}

extension EnvironmentValues {
    var sidebarToggle: SidebarToggleAction {
        get { self[SidebarToggleKey.self] }
        set { self[SidebarToggleKey.self] = newValue }
    }

    var navigationSelect: NavigationSelectAction {
        get { self[NavigationSelectKey.self] }
        set { self[NavigationSelectKey.self] = newValue }
    }
}

private struct SidebarButtonModifier: ViewModifier {
    @Environment(\.sidebarToggle) private var sidebarToggle

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: sidebarToggle.perform) {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
    }
}

extension View {
    fileprivate func withSidebarButton() -> some View {
        modifier(SidebarButtonModifier())
    }
    fileprivate func withTopToolbar() -> some View {
        modifier(SidebarButtonModifier())
    }
}

@MainActor
extension Route {
    @ViewBuilder
    func destination() -> some View {
        switch self {
        case .memos:
            MemosList(tag: nil)
                .withTopToolbar()
        case .resources:
            Resources()
                .withTopToolbar()
        case .archived:
            ArchivedMemosList()
                .withTopToolbar()
        case .tag(let tag):
            MemosList(tag: tag)
        case .settings:
            Settings()
        case .explore:
            Explore()
                .withTopToolbar()
        case .memosAccount(let accountKey):
            MemosAccountView(accountKey: accountKey)
        }
    }
}

@MainActor
extension View {
    func withSheetDestinations(sheetDestinations: Binding<SheetDestination?>) -> some View {
        sheet(item: sheetDestinations) { destination in
            switch destination {
            case .newMemo:
                MemoInput(memo: nil)
                    .withEnvironments()
            case .editMemo(let memo):
                MemoInput(memo: memo)
                    .withEnvironments()
            case .addAccount:
                AddMemosAccountView()
                    .withEnvironments()
            }
        }
    }
    
    func withEnvironments() -> some View {
        environment(Container.shared.accountViewModel())
            .environment(Container.shared.accountManager())
            .environment(Container.shared.appInfo())
            .environment(Container.shared.appPath())
            .environment(Container.shared.memosViewModel())
    }
}
