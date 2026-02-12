//
//  DailyReview.swift
//  MoeMemos
//

import SwiftUI
import Account
import Models
import Env
import Factory
import MarkdownUI

@MainActor
@Observable
final class DailyReviewViewModel {
    @ObservationIgnored
    @Injected(\.accountManager) private var accountManager

    private(set) var content: String = ""
    private(set) var loading = false
    private(set) var errorMessage: String?

    private var service: RemoteService { get throws { try accountManager.mustCurrentService } }

    func generate(for day: Date) async {
        do {
            loading = true
            errorMessage = nil

            content = try await service.getDailyReview(date: day, timezone: .current)

            loading = false
        } catch {
            loading = false
            self.errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func clearContent() {
        content = ""
    }
}

struct DailyReview: View {
    @State private var viewModel = DailyReviewViewModel()
    @State private var day: Date = Calendar.current.startOfDay(for: .now)
    @State private var showingError = false

    var body: some View {
        let content = viewModel.content

        VStack(spacing: 0) {
            HStack {
                DatePicker(
                    "",
                    selection: $day,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.compact)
                .labelsHidden()

                Spacer()

                Button {
                    Task { await viewModel.generate(for: day) }
                } label: {
                    Text("memo.daily-review.generate")
                }
                .disabled(viewModel.loading)

                if viewModel.loading {
                    ProgressView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                Section {
                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("memo.daily-review.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownView(content)
                    }
                } header: {
                    Text("memo.daily-review.result")
                }
            }
            .listStyle(InsetGroupedListStyle())
        }
        .navigationTitle("memo.daily-review")
        .onAppear {
            Task { await viewModel.generate(for: day) }
        }
        .onChange(of: day) { _, newValue in
            Task {
                viewModel.clearContent()
                await viewModel.generate(for: newValue)
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showingError = (newValue != nil)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
