//
//  Memo.swift
//  MoeMemos
//
//  Created by Mudkip on 2022/9/4.
//

import Foundation
import SwiftUI
import Models

extension MemoVisibility {
    var title: LocalizedStringKey {
        switch self {
        case .public:
            return "memo.visibility.public"
        case .local:
            return "memo.visibility.protected"
        case .private:
            return "memo.visibility.private"
        case .direct:
            return "memo.visibility.direct"
        case .unlisted:
            return "memo.visibility.unlisted"
        }
    }
    
    var iconName: String {
        switch self {
        case .public:
            return "globe"
        case .local:
            return "house"
        case .private:
            return "lock"
        case .direct:
            return "envelope"
        case .unlisted:
            return "lock.open"
        }
    }
}

extension Memo {
    func renderTime() -> String {
        return Self.absoluteTimeFormatter.string(from: createdAt)
    }

    private static let absoluteTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
