//
//  Route.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/10/30.
//

import Models
import Foundation
import Observation
import Factory

public enum Route: Hashable {
    case memos
    case dailyReview
    case memoInsight
    case resources
    case archived
    case tag(Tag)
    case settings
    case explore
    case memosAccount(String)
}

public enum SheetDestination: Identifiable, Hashable {
    case newMemo
    case editMemo(Memo)
    case addAccount
    case subscription
    
    public var id: String {
        switch self {
        case .newMemo:
            return "newMemo"
        case .editMemo:
            return "editMemo"
        case .addAccount:
            return "addAccount"
        case .subscription:
            return "subscription"
        }
    }
}

@Observable public final class AppPath: Sendable {
    @MainActor
    public var presentedSheet: SheetDestination?

    // Prefill content/resources for the next new memo sheet.
    // This is consumed by `MemoInput` when `memo == nil`.
    @MainActor
    public var newMemoPrefillContent: String?

    @MainActor
    public var newMemoPrefillResources: [Resource] = []

    // When set, the memos list should filter to this day.
    @MainActor
    public var selectedMemoDay: Date?
    
    // Subscription view model
    @MainActor
    public var subscriptionViewModel: Any?
    
    public init() {}
}

public extension Container {
    var appPath: Factory<AppPath> {
        self { AppPath() }.shared
    }
}
