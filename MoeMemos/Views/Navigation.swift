//
//  Navigation.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/10/30.
//

import SwiftUI
import Env

struct Navigation: View {
    @Binding var selection: Route?
    @State private var path = NavigationPath()
    @State private var isSidebarVisible = false
    @State private var dragOffset: CGFloat = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision {
            NavigationSplitView(columnVisibility: $columnVisibility, sidebar: {
                Sidebar(selection: $selection)
            }) {
                NavigationStack {
                    Group {
                        if let selection = selection {
                            selection.destination()
                        } else {
                            EmptyView()
                        }
                    }.navigationDestination(for: Route.self) { route in
                        route.destination()
                    }
                }
                .environment(\.navigationSelect, NavigationSelectAction { route in
                    selection = route
                })
            }
            .environment(\.sidebarToggle, SidebarToggleAction {
                withAnimation(.easeOut) {
                    columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                }
            })
        } else {
            let sidebarWidth = UIScreen.main.bounds.width * 0.8
            NavigationStack(path: $path) {
                ZStack(alignment: .leading) {
                    Group {
                        if let selection = selection {
                            selection.destination()
                        } else {
                            EmptyView()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onEnded { value in
                                if value.translation.width > 40 {
                                    withAnimation(.easeOut) {
                                        isSidebarVisible = true
                                    }
                                }
                            }
                    )
                }
                .navigationDestination(for: Route.self) { route in
                    route.destination()
                }
                .environment(\.sidebarToggle, SidebarToggleAction {
                    withAnimation(.easeOut) {
                        isSidebarVisible = true
                    }
                })
                .environment(\.navigationSelect, NavigationSelectAction { route in
                    selection = route
                })
            }
            .overlay(alignment: .leading) {
                if isSidebarVisible {
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut) {
                                    isSidebarVisible = false
                                }
                            }

                        Sidebar(selection: $selection, onSidebarItemSelect: {
                            withAnimation(.easeOut) {
                                isSidebarVisible = false
                            }
                        })
                            .frame(width: sidebarWidth)
                            .background(Color(UIColor.systemBackground))
                            .offset(x: dragOffset) // Removed .ignoresSafeArea()
                            .transition(.move(edge: .leading))
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let translation = value.translation.width
                                        if translation < 0 {
                                            dragOffset = translation
                                        }
                                    }
                                    .onEnded { value in
                                        let shouldHide = value.translation.width < -sidebarWidth * 0.3
                                        withAnimation(.easeOut) {
                                            if shouldHide {
                                                isSidebarVisible = false
                                            }
                                            dragOffset = 0
                                        }
                                    }
                            )
                    }
                    .zIndex(100)
                }
            }
            .onChange(of: selection) { _, _ in
                withAnimation(.easeOut) {
                    isSidebarVisible = false
                }
                // Clear pushed destinations when switching top-level routes.
                path = NavigationPath()
            }
        }
    }
}
