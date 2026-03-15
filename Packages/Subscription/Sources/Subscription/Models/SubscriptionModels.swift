import Foundation

public enum VipType: String, Codable, Sendable {
    case unspecified = "VIP_TYPE_UNSPECIFIED"
    case none = "NONE"
    case trial = "TRIAL"
    case subscription = "SUBSCRIPTION"
}

public enum SubscriptionState: String, Codable, Sendable {
    case unspecified = "SUBSCRIPTION_STATE_UNSPECIFIED"
    case active = "ACTIVE"
    case expired = "EXPIRED"
    case gracePeriod = "GRACE_PERIOD"
    case billingRetry = "BILLING_RETRY"
    case cancelled = "CANCELLED"
}

public struct Subscription: Codable, Sendable {
    public let productId: String
    public let state: SubscriptionState
    public let purchaseDate: Date?
    public let expiresDate: Date?
    public let isTrial: Bool
    public let willRenew: Bool
    public let originalTransactionId: String
    
    public init(
        productId: String,
        state: SubscriptionState,
        purchaseDate: Date?,
        expiresDate: Date?,
        isTrial: Bool,
        willRenew: Bool,
        originalTransactionId: String
    ) {
        self.productId = productId
        self.state = state
        self.purchaseDate = purchaseDate
        self.expiresDate = expiresDate
        self.isTrial = isTrial
        self.willRenew = willRenew
        self.originalTransactionId = originalTransactionId
    }
}

public struct TrialInfo: Codable, Sendable {
    public let trialUsed: Bool
    public let trialStartDate: Date?
    public let trialEndDate: Date?
    public let daysRemaining: Int?
    
    public init(
        trialUsed: Bool,
        trialStartDate: Date?,
        trialEndDate: Date?,
        daysRemaining: Int?
    ) {
        self.trialUsed = trialUsed
        self.trialStartDate = trialStartDate
        self.trialEndDate = trialEndDate
        self.daysRemaining = daysRemaining
    }
}

public struct SubscriptionStatus: Codable, Sendable {
    public let name: String
    public let isVip: Bool
    public let vipType: VipType
    public let subscription: Subscription?
    public let trialInfo: TrialInfo?
    public let storageQuotaBytes: Int64
    public let storageUsedBytes: Int64
    public let storageExceeded: Bool
    
    public init(
        name: String,
        isVip: Bool,
        vipType: VipType,
        subscription: Subscription?,
        trialInfo: TrialInfo?,
        storageQuotaBytes: Int64,
        storageUsedBytes: Int64,
        storageExceeded: Bool
    ) {
        self.name = name
        self.isVip = isVip
        self.vipType = vipType
        self.subscription = subscription
        self.trialInfo = trialInfo
        self.storageQuotaBytes = storageQuotaBytes
        self.storageUsedBytes = storageUsedBytes
        self.storageExceeded = storageExceeded
    }
    
    public var formattedQuota: String {
        ByteCountFormatter.string(fromByteCount: storageQuotaBytes, countStyle: .file)
    }
    
    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: storageUsedBytes, countStyle: .file)
    }
    
    public var usedPercentage: Double {
        guard storageQuotaBytes > 0 else { return 0 }
        return Double(storageUsedBytes) / Double(storageQuotaBytes) * 100
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case isVip
        case vipType
        case subscription
        case trialInfo
        case storageQuotaBytes
        case storageUsedBytes
        case storageExceeded
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isVip = try container.decode(Bool.self, forKey: .isVip)
        vipType = try container.decode(VipType.self, forKey: .vipType)
        subscription = try container.decodeIfPresent(Subscription.self, forKey: .subscription)
        trialInfo = try container.decodeIfPresent(TrialInfo.self, forKey: .trialInfo)
        storageExceeded = try container.decode(Bool.self, forKey: .storageExceeded)
        
        if let intValue = try? container.decode(Int64.self, forKey: .storageQuotaBytes) {
            storageQuotaBytes = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .storageQuotaBytes),
                  let parsed = Int64(stringValue) {
            storageQuotaBytes = parsed
        } else {
            storageQuotaBytes = 0
        }
        
        if let intValue = try? container.decode(Int64.self, forKey: .storageUsedBytes) {
            storageUsedBytes = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .storageUsedBytes),
                  let parsed = Int64(stringValue) {
            storageUsedBytes = parsed
        } else {
            storageUsedBytes = 0
        }
    }
}

public struct StorageUsage: Codable, Sendable {
    public let name: String
    public let usedBytes: Int64
    public let quotaBytes: Int64
    public let usedPercentage: Int32
    public let breakdown: StorageBreakdown?
    public let quotaExceeded: Bool
    
    public init(
        name: String,
        usedBytes: Int64,
        quotaBytes: Int64,
        usedPercentage: Int32,
        breakdown: StorageBreakdown?,
        quotaExceeded: Bool
    ) {
        self.name = name
        self.usedBytes = usedBytes
        self.quotaBytes = quotaBytes
        self.usedPercentage = usedPercentage
        self.breakdown = breakdown
        self.quotaExceeded = quotaExceeded
    }
    
    public var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)
    }
    
    public var formattedQuota: String {
        ByteCountFormatter.string(fromByteCount: quotaBytes, countStyle: .file)
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case usedBytes
        case quotaBytes
        case usedPercentage
        case breakdown
        case quotaExceeded
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        usedPercentage = try container.decode(Int32.self, forKey: .usedPercentage)
        breakdown = try container.decodeIfPresent(StorageBreakdown.self, forKey: .breakdown)
        quotaExceeded = try container.decode(Bool.self, forKey: .quotaExceeded)
        
        if let intValue = try? container.decode(Int64.self, forKey: .usedBytes) {
            usedBytes = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .usedBytes),
                  let parsed = Int64(stringValue) {
            usedBytes = parsed
        } else {
            usedBytes = 0
        }
        
        if let intValue = try? container.decode(Int64.self, forKey: .quotaBytes) {
            quotaBytes = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .quotaBytes),
                  let parsed = Int64(stringValue) {
            quotaBytes = parsed
        } else {
            quotaBytes = 0
        }
    }
}

public struct StorageBreakdown: Codable, Sendable {
    public let attachmentBytes: Int64
    public let memoContentBytes: Int64
    
    public init(attachmentBytes: Int64, memoContentBytes: Int64) {
        self.attachmentBytes = attachmentBytes
        self.memoContentBytes = memoContentBytes
    }
    
    enum CodingKeys: String, CodingKey {
        case attachmentBytes
        case memoContentBytes
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        if let intValue = try? container.decode(Int64.self, forKey: .attachmentBytes) {
            attachmentBytes = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .attachmentBytes),
                  let parsed = Int64(stringValue) {
            attachmentBytes = parsed
        } else {
            attachmentBytes = 0
        }
        
        if let intValue = try? container.decode(Int64.self, forKey: .memoContentBytes) {
            memoContentBytes = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .memoContentBytes),
                  let parsed = Int64(stringValue) {
            memoContentBytes = parsed
        } else {
            memoContentBytes = 0
        }
    }
}

public enum SubscriptionError: Error, LocalizedError, Sendable {
    case userCancelled
    case pending
    case verificationFailed
    case noProductsAvailable
    case networkError(Error)
    case invalidResponse
    case notAuthenticated
    
    public var errorDescription: String? {
        switch self {
        case .userCancelled:
            return NSLocalizedString("subscription.error.userCancelled", comment: "")
        case .pending:
            return NSLocalizedString("subscription.error.pending", comment: "")
        case .verificationFailed:
            return NSLocalizedString("subscription.error.verificationFailed", comment: "")
        case .noProductsAvailable:
            return NSLocalizedString("subscription.error.noProductsAvailable", comment: "")
        case .networkError(let error):
            return error.localizedDescription
        case .invalidResponse:
            return NSLocalizedString("subscription.error.invalidResponse", comment: "")
        case .notAuthenticated:
            return NSLocalizedString("subscription.error.notAuthenticated", comment: "")
        }
    }
}

public protocol SubscriptionServiceProtocol: Sendable {
    func getSubscriptionStatus() async throws -> SubscriptionStatus
    func validateReceipt(receiptData: String, sandbox: Bool) async throws -> SubscriptionStatus
    func restorePurchases() async throws -> SubscriptionStatus
    func getStorageUsage() async throws -> StorageUsage
    /// 同步订阅状态到后端（用于退款检测后通知后端更新）
    func syncSubscriptionStatus(isVip: Bool, productId: String?, expiresDate: Date?) async throws -> SubscriptionStatus
}
