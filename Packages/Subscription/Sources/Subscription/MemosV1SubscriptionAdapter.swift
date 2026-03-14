import Foundation
import MemosV1Service

@MainActor
public final class MemosV1SubscriptionAdapter: SubscriptionServiceProtocol {
    private let service: MemosV1Service
    
    public init(service: MemosV1Service) {
        self.service = service
    }
    
    public func getSubscriptionStatus() async throws -> SubscriptionStatus {
        let url = service.subscriptionHostURL.appendingPathComponent("api/v1/users/me/subscription")
        let data = try await service.authenticatedDataRequest(url: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        return try decoder.decode(SubscriptionStatus.self, from: data)
    }
    
    public func validateReceipt(receiptData: String, sandbox: Bool) async throws -> SubscriptionStatus {
        let url = service.subscriptionHostURL.appendingPathComponent("api/v1/users/me/subscription:validateReceipt")
        
        let body: [String: Any] = [
            "parent": "users/me",
            "receiptData": receiptData,
            "sandbox": sandbox
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        let data = try await service.authenticatedDataRequest(url: url, method: "POST", body: bodyData)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        let responseObj = try decoder.decode(ValidateReceiptResponse.self, from: data)
        
        if !responseObj.valid {
            throw SubscriptionError.verificationFailed
        }
        
        guard let status = responseObj.status else {
            throw SubscriptionError.invalidResponse
        }
        
        return status
    }
    
    public func restorePurchases() async throws -> SubscriptionStatus {
        let url = service.subscriptionHostURL.appendingPathComponent("api/v1/users/me/subscription:restore")
        
        let body: [String: Any] = ["parent": "users/me"]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        
        let data = try await service.authenticatedDataRequest(url: url, method: "POST", body: bodyData)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        let responseObj = try decoder.decode(RestorePurchasesResponse.self, from: data)
        
        return responseObj.status
    }
    
    public func getStorageUsage() async throws -> StorageUsage {
        let url = service.subscriptionHostURL.appendingPathComponent("api/v1/users/me/storage")
        let data = try await service.authenticatedDataRequest(url: url)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        return try decoder.decode(StorageUsage.self, from: data)
    }
}

private struct ValidateReceiptResponse: Codable {
    let status: SubscriptionStatus?
    let valid: Bool
    let errorMessage: String?
}

private struct RestorePurchasesResponse: Codable {
    let status: SubscriptionStatus
    let restored: Bool
    let restoredCount: Int
}

private extension JSONDecoder.DateDecodingStrategy {
    static let customISO8601 = custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        
        let formatters: [ISO8601DateFormatter] = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let formatter2 = ISO8601DateFormatter()
            formatter2.formatOptions = [.withInternetDateTime]
            return [formatter, formatter2]
        }()
        
        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
    }
}
