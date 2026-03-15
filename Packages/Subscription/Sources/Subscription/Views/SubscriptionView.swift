import SwiftUI
import StoreKit

private extension String {
    var localized: String {
        NSLocalizedString(self, bundle: .module, comment: "")
    }
}

public struct SubscriptionView: View {
    @StateObject private var viewModel: SubscriptionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var hasLoadedData = false
    
    public init(viewModel: SubscriptionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        print("[SubscriptionView] init")
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("subscription.title".localized)
                    .font(.headline)
                Spacer()
                Button("common.close".localized) {
                    print("[SubscriptionView] Close button tapped")
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 24) {
                    if viewModel.authenticationError {
                        AuthenticationErrorBanner()
                    } else if viewModel.apiUnavailable {
                        APIUnavailableBanner()
                    }
                    
                    if let status = viewModel.subscriptionStatus {
                        VIPStatusCard(status: status)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                    }
                    
                    if let usage = viewModel.storageUsage {
                        StorageUsageCard(usage: usage)
                    }
                    
                    if viewModel.subscriptionStatus?.isVip == false {
                        PurchaseSection(
                            products: viewModel.storeKitManager.products,
                            mockProducts: viewModel.storeKitManager.mockProducts,
                            isLoading: viewModel.isLoading,
                            onPurchase: {
                                print("[SubscriptionView] Purchase button tapped")
                                Task { await viewModel.purchaseSubscription() }
                            }
                        )
                    }
                    
                    Button {
                        print("[SubscriptionView] Restore button tapped")
                        Task { await viewModel.restorePurchases() }
                    } label: {
                        Text("subscription.restore".localized)
                            .font(.subheadline)
                    }
                    .padding(.top, 8)
                    .disabled(viewModel.isLoading)
                    
                    TermsPrivacySection()
                }
                .padding()
            }
        }
        .task {
            if !hasLoadedData {
                print("[SubscriptionView] task started, loading data...")
                hasLoadedData = true
                await viewModel.loadData()
                print("[SubscriptionView] task completed")
            }
        }
        .alert("subscription.purchase.success".localized, isPresented: $viewModel.showingPurchaseSuccess) {
            Button("common.ok".localized, role: .cancel) { 
                print("[SubscriptionView] Purchase success alert dismissed")
            }
        }
        .alert("subscription.restore.success".localized, isPresented: $viewModel.showingRestoreSuccess) {
            Button("common.ok".localized, role: .cancel) { 
                print("[SubscriptionView] Restore success alert dismissed")
            }
        }
        .alert("common.error".localized, isPresented: .init(
            get: { 
                let hasError = viewModel.error != nil
                if hasError {
                    print("[SubscriptionView] Error alert showing: \(viewModel.error?.localizedDescription ?? "unknown")")
                }
                return hasError
            },
            set: { 
                print("[SubscriptionView] Error alert dismissed")
                if !$0 { viewModel.error = nil } 
            }
        )) {
            Button("common.ok".localized, role: .cancel) { }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .onAppear {
            print("[SubscriptionView] onAppear")
        }
        .onDisappear {
            print("[SubscriptionView] onDisappear")
        }
    }
}

struct AuthenticationErrorBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.red)
            Text("subscription.authentication.error".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemRed).opacity(0.1))
        .cornerRadius(12)
    }
}

struct APIUnavailableBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("subscription.api.unavailable".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemYellow).opacity(0.1))
        .cornerRadius(12)
    }
}

struct VIPStatusCard: View {
    let status: SubscriptionStatus
    
    var body: some View {
        VStack(spacing: 12) {
            if status.isVip {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.yellow)
                Text("subscription.vip.active".localized)
                    .font(.title2)
                    .fontWeight(.bold)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("subscription.vip.inactive".localized)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            if let subscription = status.subscription {
                VStack(spacing: 4) {
                    Text("subscription.expires".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let expiresDate = subscription.expiresDate {
                        Text(expiresDate, style: .date)
                            .font(.headline)
                    }
                }
            } else if let trial = status.trialInfo, let daysRemaining = trial.daysRemaining, daysRemaining > 0 {
                VStack(spacing: 4) {
                    Text("subscription.trial.daysRemaining".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(daysRemaining)")
                        .font(.headline)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
}

struct StorageUsageCard: View {
    let usage: StorageUsage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("subscription.storage.title".localized)
                .font(.headline)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(usage.quotaExceeded ? .red : .blue)
                        .frame(width: min(CGFloat(usage.usedPercentage) / 100 * geometry.size.width, geometry.size.width), height: 8)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text(usage.formattedUsed)
                Spacer()
                Text(usage.formattedQuota)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            
            if usage.quotaExceeded {
                Label("subscription.storage.exceeded".localized, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
}

struct PurchaseSection: View {
    let products: [Product]
    #if DEBUG
    let mockProducts: [StoreKitManager.MockProduct]
    #endif
    let isLoading: Bool
    let onPurchase: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("subscription.purchase.title".localized)
                .font(.headline)
            
            if isLoading {
                HStack {
                    ProgressView()
                    Text("subscription.loading.products".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if !products.isEmpty {
                // 使用真实的 StoreKit 产品
                ForEach(products) { product in
                    ProductCard(product: product, onPurchase: onPurchase)
                }
            } else if hasMockProducts {
                // 使用模拟产品（DEBUG 真机测试）
                #if DEBUG
                ForEach(mockProducts) { mockProduct in
                    MockProductCard(mockProduct: mockProduct, onPurchase: onPurchase)
                }
                #endif
            } else {
                VStack(spacing: 12) {
                    Text("subscription.products.unavailable".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("subscription.products.unavailable.hint".localized)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    private var hasMockProducts: Bool {
        #if DEBUG
        return !mockProducts.isEmpty
        #else
        return false
        #endif
    }
}

#if DEBUG
struct MockProductCard: View {
    let mockProduct: StoreKitManager.MockProduct
    let onPurchase: () -> Void
    
    var body: some View {
        Button {
            onPurchase()
        } label: {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mockProduct.displayName)
                            .font(.headline)
                        Text(mockProduct.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(mockProduct.displayPrice)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text("subscription.purchase.button".localized)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 2)
        }
    }
}
#endif

struct ProductCard: View {
    let product: Product
    let onPurchase: () -> Void
    
    var body: some View {
        Button {
            onPurchase()
        } label: {
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(product.displayName)
                            .font(.headline)
                        Text(product.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(product.displayPrice)
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Text("subscription.purchase.button".localized)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 2)
        }
    }
}

struct TermsPrivacySection: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("subscription.terms.intro".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Link("subscription.terms.link".localized, destination: URL(string: "https://memos.app/terms")!)
                Link("subscription.privacy.link".localized, destination: URL(string: "https://memos.app/privacy")!)
            }
            .font(.caption)
        }
        .padding(.top, 8)
    }
}
