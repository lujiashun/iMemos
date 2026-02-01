import SwiftUI
import Models

struct EditNicknameView: View {
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(currentNickname: String) {
        _nickname = State(initialValue: currentNickname)
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "account.nickname"), text: $nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("account.nickname")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("account.save") {
                    Task { @MainActor in
                        await save()
                    }
                }
                .disabled(isSaving)
            }
        }
    }

    @MainActor
    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            try await accountViewModel.updateNickname(to: nickname)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
