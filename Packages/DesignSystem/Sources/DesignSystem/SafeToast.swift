import SwiftUI

public struct SafeToastModifier: ViewModifier {
    @Binding var isPresenting: Bool
    let message: String?
    let systemImage: String?

    public init(isPresenting: Binding<Bool>, message: String? = nil, systemImage: String? = nil) {
        self._isPresenting = isPresenting
        self.message = message
        self.systemImage = systemImage
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isPresenting, let message = message {
                    HStack(spacing: 8) {
                        if let systemImage = systemImage {
                            Image(systemName: systemImage)
                        }
                        Text(message)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onTapGesture { withAnimation { isPresenting = false } }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .overlay {
                if isPresenting && message == nil {
                    ZStack {
                        Color.black.opacity(0.001)
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding(16)
                            .background(.regularMaterial)
                            .cornerRadius(12)
                            .shadow(radius: 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
    }
}

public extension View {
    func safeToast(isPresenting: Binding<Bool>, message: String? = nil, systemImage: String? = nil) -> some View {
        modifier(SafeToastModifier(isPresenting: isPresenting, message: message, systemImage: systemImage))
    }

    func safeLoading(isPresenting: Binding<Bool>) -> some View {
        safeToast(isPresenting: isPresenting, message: nil, systemImage: nil)
    }
}
