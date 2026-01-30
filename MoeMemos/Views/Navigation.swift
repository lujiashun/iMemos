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
    @State private var isSidebarVisible = true
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad || UIDevice.current.userInterfaceIdiom == .vision {
            NavigationSplitView(sidebar: {
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

                    if isSidebarVisible {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeOut) {
                                    isSidebarVisible = false
                                }
                            }
                    }

                    Sidebar(selection: $selection)
                        .frame(width: sidebarWidth)
                        .background(.regularMaterial)
                        .offset(x: (isSidebarVisible ? 0 : -sidebarWidth) + dragOffset)
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
                                        isSidebarVisible = !shouldHide
                                        dragOffset = 0
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
            .onChange(of: selection) { _, _ in
                withAnimation(.easeOut) {
                    isSidebarVisible = false
                }
            }
        }
    }
}
