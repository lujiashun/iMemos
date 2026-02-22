//
//  MoeMemosShareView.swift
//  MoeMemosShareExtension
//
//  Created by Mudkip on 2022/12/1.
//

import SwiftUI
import DesignSystem

struct MoeMemosShareView: View {
    let alertType: AlertType
    @State var isPresenting = true
    
    init(alertType: AlertType = .loading) {
        self.alertType = alertType
    }
    
    private var message: String? {
        switch alertType {
        case .systemImage(_, let title): return title
        case .loading: return nil
        }
    }

    private var systemImageName: String? {
        switch alertType {
        case .systemImage(let name, _): return name
        case .loading: return nil
        }
    }

    var body: some View {
        Color.clear
            .safeToast(isPresenting: $isPresenting, message: message, systemImage: systemImageName)
    }
}

#Preview {
    MoeMemosShareView()
}
