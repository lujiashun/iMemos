import SwiftUI
import Models

struct ChangePasswordView: View {
    @Environment(AccountViewModel.self) private var accountViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmNewPassword = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField(String(localized: "account.password.old"), text: $oldPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                SecureField(String(localized: "account.password.new"), text: $newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField(String(localized: "account.password.confirm"), text: $confirmNewPassword)
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
        .navigationTitle("account.change-password")
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

        if newPassword != confirmNewPassword {
            errorMessage = String(localized: "account.password.mismatch")
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await accountViewModel.changePassword(oldPassword: oldPassword, newPassword: newPassword)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
