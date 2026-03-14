import Foundation
import MemosV1Service

public enum SubscriptionFactory {
    @MainActor
    public static func createViewModel(service: MemosV1Service?) -> SubscriptionViewModel {
        let storeKitManager = StoreKitManager()
        let apiClient: SubscriptionServiceProtocol
        
        if let service = service {
            apiClient = MemosV1SubscriptionAdapter(service: service)
        } else {
            apiClient = MockSubscriptionService()
        }
        
        return SubscriptionViewModel(storeKitManager: storeKitManager, apiClient: apiClient)
    }
}

public final class MockSubscriptionService: SubscriptionServiceProtocol {
    public init() {}
    
    public func getSubscriptionStatus() async throws -> SubscriptionStatus {
        print("[MockSubscriptionService] getSubscriptionStatus called")
        return SubscriptionStatus(
            name: "mock",
            isVip: false,
            vipType: .none,
            subscription: nil,
            trialInfo: nil,
            storageQuotaBytes: 50 * 1024 * 1024,
            storageUsedBytes: 0,
            storageExceeded: false
        )
    }
    
    public func validateReceipt(receiptData: String, sandbox: Bool) async throws -> SubscriptionStatus {
        print("[MockSubscriptionService] validateReceipt called")
        throw SubscriptionError.verificationFailed
    }
    
    public func restorePurchases() async throws -> SubscriptionStatus {
        print("[MockSubscriptionService] restorePurchases called")
        return SubscriptionStatus(
            name: "mock",
            isVip: false,
            vipType: .none,
            subscription: nil,
            trialInfo: nil,
            storageQuotaBytes: 50 * 1024 * 1024,
            storageUsedBytes: 0,
            storageExceeded: false
        )
    }
    
    public func getStorageUsage() async throws -> StorageUsage {
        print("[MockSubscriptionService] getStorageUsage called")
        return StorageUsage(
            name: "mock",
            usedBytes: 0,
            quotaBytes: 50 * 1024 * 1024,
            usedPercentage: 0,
            breakdown: nil,
            quotaExceeded: false
        )
    }
}
