import Foundation
import StoreKit

@MainActor
public class SubscriptionViewModel: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public private(set) var subscriptionStatus: SubscriptionStatus?
    @Published public private(set) var storageUsage: StorageUsage?
    @Published public private(set) var isLoading = false
    @Published public var error: Error?
    @Published public var showingPurchaseSuccess = false
    @Published public var showingRestoreSuccess = false
    @Published public var apiUnavailable = false
    @Published public var authenticationError = false
    
    public let storeKitManager: StoreKitManager
    private var apiClient: SubscriptionServiceProtocol
    
    public init(storeKitManager: StoreKitManager, apiClient: SubscriptionServiceProtocol) {
        self.storeKitManager = storeKitManager
        self.apiClient = apiClient
        print("[SubscriptionViewModel] init completed")
        
        // 设置订阅状态变化回调
        setupSubscriptionChangeHandler()
    }
    
    /// 设置订阅状态变化处理
    private func setupSubscriptionChangeHandler() {
        storeKitManager.onSubscriptionChanged = { [weak self] change in
            Task { @MainActor in
                await self?.handleSubscriptionChange(change)
            }
        }
    }
    
    /// 处理订阅状态变化
    private func handleSubscriptionChange(_ change: StoreKitManager.SubscriptionChange) async {
        print("[SubscriptionViewModel] Subscription changed: type=\(change.changeType), isVip=\(change.isVip)")
        
        do {
            // 同步到后端
            let updatedStatus = try await apiClient.syncSubscriptionStatus(
                isVip: change.isVip,
                productId: change.productId,
                expiresDate: change.expiresDate
            )
            
            print("[SubscriptionViewModel] Backend sync completed, new status: isVip=\(updatedStatus.isVip)")
            
            // 更新本地状态
            self.subscriptionStatus = updatedStatus
            
            // 根据变化类型显示提示
            switch change.changeType {
            case .refund:
                print("[SubscriptionViewModel] Refund detected, subscription cancelled")
            case .purchase:
                print("[SubscriptionViewModel] New purchase confirmed")
                self.showingPurchaseSuccess = true
            case .restore:
                print("[SubscriptionViewModel] Purchase restored")
                self.showingRestoreSuccess = true
            case .expiration:
                print("[SubscriptionViewModel] Subscription expired")
            }
            
        } catch {
            print("[SubscriptionViewModel] Failed to sync subscription to backend: \(error)")
            // 即使同步失败，也更新本地 StoreKit 状态
            let subscription: Subscription?
            if change.isVip {
                subscription = Subscription(
                    productId: change.productId ?? "",
                    state: .active,
                    purchaseDate: Date(),
                    expiresDate: change.expiresDate ?? Date().addingTimeInterval(365 * 24 * 60 * 60),
                    isTrial: false,
                    willRenew: true,
                    originalTransactionId: "local_\(change.productId ?? "")"
                )
            } else {
                subscription = nil
            }
            
            self.subscriptionStatus = SubscriptionStatus(
                name: "users/me/subscription",
                isVip: change.isVip,
                vipType: change.isVip ? .subscription : .none,
                subscription: subscription,
                trialInfo: nil,
                storageQuotaBytes: change.isVip ? 5 * 1024 * 1024 * 1024 : 50 * 1024 * 1024,
                storageUsedBytes: self.storageUsage?.usedBytes ?? 0,
                storageExceeded: false
            )
        }
    }
    
    public func updateApiClient(_ client: SubscriptionServiceProtocol) {
        self.apiClient = client
        print("[SubscriptionViewModel] API client updated")
    }
    
    private func isAuthenticationError(_ error: Error) -> Bool {
        print("[SubscriptionViewModel] Checking if authentication error: \(error)")
        print("[SubscriptionViewModel] Error type: \(type(of: error))")
        print("[SubscriptionViewModel] Error description: \(error.localizedDescription)")
        
        if let subscriptionError = error as? SubscriptionError {
            switch subscriptionError {
            case .notAuthenticated:
                return true
            default:
                return false
            }
        }
        
        let errorString = error.localizedDescription.lowercased()
        let hasAuthKeyword = errorString.contains("unauthenticated") || 
               errorString.contains("401") || 
               errorString.contains("not authenticated") ||
               errorString.contains("unauthorized") ||
               errorString.contains("logged out")
        
        print("[SubscriptionViewModel] Has auth keyword: \(hasAuthKeyword)")
        return hasAuthKeyword
    }
    
    private func isApiUnavailableError(_ error: Error) -> Bool {
        print("[SubscriptionViewModel] Checking if API unavailable error: \(error)")
        
        let errorString = error.localizedDescription.lowercased()
        let hasUnavailableKeyword = errorString.contains("501") || 
               errorString.contains("not implemented") ||
               errorString.contains("500") ||
               errorString.contains("internal server error")
        
        print("[SubscriptionViewModel] Has unavailable keyword: \(hasUnavailableKeyword)")
        return hasUnavailableKeyword
    }
    
    public func loadData() async {
        print("[SubscriptionViewModel] loadData started")
        isLoading = true
        defer { 
            isLoading = false
            print("[SubscriptionViewModel] loadData completed, isLoading=\(isLoading)")
        }
        
        print("[SubscriptionViewModel] Loading StoreKit products...")
        await storeKitManager.loadProducts()
        print("[SubscriptionViewModel] StoreKit products loaded, count: \(storeKitManager.products.count)")
        
        do {
            print("[SubscriptionViewModel] Fetching subscription status and storage usage...")
            async let loadStatus = apiClient.getSubscriptionStatus()
            async let loadStorage = apiClient.getStorageUsage()
            
            subscriptionStatus = try await loadStatus
            print("[SubscriptionViewModel] Subscription status loaded: isVip=\(subscriptionStatus?.isVip ?? false)")
            
            storageUsage = try await loadStorage
            print("[SubscriptionViewModel] Storage usage loaded: \(storageUsage?.formattedUsed ?? "N/A") / \(storageUsage?.formattedQuota ?? "N/A")")
            
            apiUnavailable = false
            authenticationError = false
            error = nil
        } catch {
            print("[SubscriptionViewModel] API error: \(error)")
            print("[SubscriptionViewModel] Error type: \(type(of: error))")
            
            if isAuthenticationError(error) {
                authenticationError = true
                apiUnavailable = false
                print("[SubscriptionViewModel] Authentication error detected")
            } else if isApiUnavailableError(error) {
                apiUnavailable = true
                authenticationError = false
                print("[SubscriptionViewModel] API unavailable detected")
            } else {
                apiUnavailable = true
                authenticationError = false
                print("[SubscriptionViewModel] Unknown error, treating as API unavailable")
            }
            
            subscriptionStatus = SubscriptionStatus(
                name: "users/me/subscription",
                isVip: false,
                vipType: .none,
                subscription: nil,
                trialInfo: nil,
                storageQuotaBytes: 50 * 1024 * 1024,
                storageUsedBytes: 0,
                storageExceeded: false
            )
            storageUsage = StorageUsage(
                name: "users/me/storage",
                usedBytes: 0,
                quotaBytes: 50 * 1024 * 1024,
                usedPercentage: 0,
                breakdown: nil,
                quotaExceeded: false
            )
        }
    }
    
    public func purchaseSubscription() async {
        print("[SubscriptionViewModel] purchaseSubscription started")
        print("[SubscriptionViewModel] Current products count: \(storeKitManager.products.count)")
        #if DEBUG
        print("[SubscriptionViewModel] Current mock products count: \(storeKitManager.mockProducts.count)")
        #endif
        
        // 如果产品为空，尝试重新加载
        if storeKitManager.products.isEmpty {
            print("[SubscriptionViewModel] Products empty, reloading...")
            await storeKitManager.loadProducts()
            print("[SubscriptionViewModel] After reload, products count: \(storeKitManager.products.count)")
            #if DEBUG
            print("[SubscriptionViewModel] After reload, mock products count: \(storeKitManager.mockProducts.count)")
            #endif
        }
        
        // 检查是否有真实产品
        if let product = storeKitManager.products.first {
            // 使用真实 StoreKit 产品购买
            print("[SubscriptionViewModel] Purchasing real product: \(product.id)")
            await purchaseRealProduct(product)
        } else {
            // 没有真实产品，检查是否有模拟产品（DEBUG 模式）
            await handleNoRealProducts()
        }
    }
    
    /// 处理没有真实产品的情况
    private func handleNoRealProducts() async {
        #if DEBUG
        if let mockProduct = storeKitManager.mockProducts.first {
            // 使用模拟产品购买（DEBUG 模式）
            print("[SubscriptionViewModel] Purchasing mock product: \(mockProduct.id)")
            await purchaseMockProduct(mockProduct)
            return
        }
        #endif
        
        print("[SubscriptionViewModel] No products available for purchase")
        error = SubscriptionError.noProductsAvailable
    }
    
    #if DEBUG
    /// 模拟产品购买流程（用于 DEBUG 模式）
    private func purchaseMockProduct(_ mockProduct: StoreKitManager.MockProduct) async {
        print("[SubscriptionViewModel] Starting mock purchase for: \(mockProduct.id)")
        isLoading = true
        defer { isLoading = false }
        
        // 模拟网络延迟
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        // 模拟购买成功，先更新本地状态为 VIP
        print("[SubscriptionViewModel] Mock purchase successful, updating local state to VIP")
        
        let expiresDate = Date().addingTimeInterval(365 * 24 * 60 * 60) // 1年后过期
        
        // 创建模拟的 Subscription
        let subscription = Subscription(
            productId: mockProduct.id,
            state: .active,
            purchaseDate: Date(),
            expiresDate: expiresDate,
            isTrial: false,
            willRenew: true,
            originalTransactionId: "mock_\(mockProduct.id)"
        )
        
        // 创建模拟的 VIP 订阅状态
        subscriptionStatus = SubscriptionStatus(
            name: "users/me/subscription",
            isVip: true,
            vipType: .subscription,
            subscription: subscription,
            trialInfo: nil,
            storageQuotaBytes: 5 * 1024 * 1024 * 1024, // 5GB
            storageUsedBytes: storageUsage?.usedBytes ?? 0,
            storageExceeded: false
        )
        
        // 更新存储配额为 5GB
        if let currentUsage = storageUsage {
            let quotaBytes: Int64 = 5 * 1024 * 1024 * 1024
            let usedPercentageDouble = quotaBytes > 0 ? Double(currentUsage.usedBytes) / Double(quotaBytes) * 100 : 0
            let usedPercentage = Int32(usedPercentageDouble)
            storageUsage = StorageUsage(
                name: currentUsage.name,
                usedBytes: currentUsage.usedBytes,
                quotaBytes: quotaBytes,
                usedPercentage: usedPercentage,
                breakdown: currentUsage.breakdown,
                quotaExceeded: false
            )
        }
        
        // 显示购买成功提示
        showingPurchaseSuccess = true
        
        print("[SubscriptionViewModel] Local state updated to VIP (DEBUG mode)")
        print("[SubscriptionViewModel] Note: Server state not updated in DEBUG mode")
    }
    #endif
    
    /// 真实产品购买流程
    private func purchaseRealProduct(_ product: Product) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            guard let transaction = try await storeKitManager.purchase(product) else {
                print("[SubscriptionViewModel] Purchase returned nil transaction (user cancelled?)")
                return
            }
            
            print("[SubscriptionViewModel] Purchase successful, transaction ID: \(transaction.id)")
            
            guard let receiptURL = Bundle.main.appStoreReceiptURL,
                  let receiptData = try? Data(contentsOf: receiptURL).base64EncodedString() else {
                print("[SubscriptionViewModel] Failed to get receipt data")
                error = SubscriptionError.verificationFailed
                return
            }
            
            print("[SubscriptionViewModel] Receipt data length: \(receiptData.count)")
            
            let isSandbox: Bool
            #if DEBUG
            isSandbox = true
            #else
            isSandbox = transaction.environment == .sandbox
            #endif
            
            print("[SubscriptionViewModel] Validating receipt, sandbox=\(isSandbox)")
            
            do {
                subscriptionStatus = try await apiClient.validateReceipt(
                    receiptData: receiptData,
                    sandbox: isSandbox
                )
                print("[SubscriptionViewModel] Receipt validated successfully")
                storageUsage = try await apiClient.getStorageUsage()
                apiUnavailable = false
                authenticationError = false
            } catch {
                apiUnavailable = true
                print("[SubscriptionViewModel] Receipt validation API error: \(error)")
            }
            
            showingPurchaseSuccess = true
            error = nil
            print("[SubscriptionViewModel] Purchase flow completed successfully")
            
        } catch {
            self.error = error
            print("[SubscriptionViewModel] Purchase failed with error: \(error)")
        }
    }
    
    public func restorePurchases() async {
        print("[SubscriptionViewModel] restorePurchases started")
        isLoading = true
        defer { 
            isLoading = false
            print("[SubscriptionViewModel] restorePurchases completed, isLoading=\(isLoading)")
        }
        
        do {
                print("[SubscriptionViewModel] Calling StoreKit restorePurchases...")
                try await storeKitManager.restorePurchases()
                print("[SubscriptionViewModel] StoreKit restore completed")
                
                do {
                    print("[SubscriptionViewModel] Calling API restorePurchases...")
                    subscriptionStatus = try await apiClient.restorePurchases()
                    print("[SubscriptionViewModel] API restore completed, isVip=\(subscriptionStatus?.isVip ?? false)")
                    
                    storageUsage = try await apiClient.getStorageUsage()
                    print("[SubscriptionViewModel] Storage usage refreshed")
                    apiUnavailable = false
                    authenticationError = false
                } catch {
                    if isAuthenticationError(error) {
                        authenticationError = true
                        print("[SubscriptionViewModel] Authentication error during restore")
                    } else {
                        apiUnavailable = true
                        print("[SubscriptionViewModel] Restore API error: \(error)")
                    }
                }
                
                showingRestoreSuccess = true
                error = nil
                print("[SubscriptionViewModel] Restore flow completed, showingRestoreSuccess=\(showingRestoreSuccess)")
            
        } catch {
            self.error = error
            print("[SubscriptionViewModel] Restore failed with error: \(error)")
        }
    }
    
    public func refreshStatus() async {
        print("[SubscriptionViewModel] refreshStatus started")
        isLoading = true
        defer { isLoading = false }
        
        do {
            subscriptionStatus = try await apiClient.getSubscriptionStatus()
            storageUsage = try await apiClient.getStorageUsage()
            apiUnavailable = false
            authenticationError = false
            error = nil
            print("[SubscriptionViewModel] Status refreshed successfully")
        } catch {
            if isAuthenticationError(error) {
                authenticationError = true
            } else {
                apiUnavailable = true
            }
            print("[SubscriptionViewModel] Failed to refresh status: \(error)")
        }
    }
}
