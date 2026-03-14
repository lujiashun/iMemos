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
        guard let product = storeKitManager.products.first else {
            print("[SubscriptionViewModel] No products available for purchase")
            error = SubscriptionError.noProductsAvailable
            return
        }
        
        print("[SubscriptionViewModel] Purchasing product: \(product.id)")
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
