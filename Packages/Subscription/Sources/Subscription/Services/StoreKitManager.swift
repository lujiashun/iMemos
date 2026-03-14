import Foundation
import StoreKit

@MainActor
public final class StoreKitManager: ObservableObject {
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedSubscriptions: [Product] = []
    @Published public private(set) var isLoading = false
    @Published public var error: Error?
    
    private let productIDs = ["com.memos.vip.yearly"]
    private var updateListenerTask: Task<Void, Error>?
    
    public init() {
        #if DEBUG
        print("[StoreKitManager] Running in DEBUG configuration")
        #else
        print("[StoreKitManager] Running in RELEASE configuration")
        #endif
        
        updateListenerTask = Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try Self.checkVerified(result)
                    await transaction.finish()
                    await self.updatePurchasedSubscriptions()
                } catch {
                    print("Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        print("[StoreKitManager] ========================================")
        print("[StoreKitManager] loadProducts started")
        print("[StoreKitManager] ========================================")
        print("[StoreKitManager] productIDs: \(productIDs)")
        print("[StoreKitManager] Main bundle path: \(Bundle.main.bundlePath)")
        print("[StoreKitManager] Main bundle resource path: \(Bundle.main.resourcePath ?? "nil")")
        
        // 1. 检查 bundle 中是否有 storekit 文件
        print("[StoreKitManager] [1/4] Checking if Subscription.storekit exists...")
        if let storeKitURL = Bundle.main.url(forResource: "Subscription", withExtension: "storekit") {
            print("[StoreKitManager] ✅ Found Subscription.storekit at: \(storeKitURL)")
            
            // 2. 读取并打印文件内容
            print("[StoreKitManager] [2/4] Reading file content...")
            do {
                let fileContent = try String(contentsOf: storeKitURL, encoding: .utf8)
                print("[StoreKitManager] ✅ File content:")
                print("[StoreKitManager] ----------------------------------------")
                print(fileContent)
                print("[StoreKitManager] ----------------------------------------")
                
                // 3. 解析 JSON 并检查格式
                print("[StoreKitManager] [3/4] Parsing JSON and checking format...")
                if let jsonData = fileContent.data(using: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] {
                        print("[StoreKitManager] ✅ JSON parsed successfully")
                        
                        // 检查 version
                        if let version = json["version"] as? [String: Any] {
                            print("[StoreKitManager] Version: major=\(version["major"] ?? "nil"), minor=\(version["minor"] ?? "nil")")
                        } else {
                            print("[StoreKitManager] ⚠️ Version not found or invalid")
                        }
                        
                        // 检查 products 数组
                        if let productsArray = json["products"] as? [Any] {
                            print("[StoreKitManager] ✅ 'products' array found, count: \(productsArray.count)")
                            if productsArray.isEmpty {
                                print("[StoreKitManager] ⚠️ 'products' array is EMPTY!")
                            }
                        } else {
                            print("[StoreKitManager] ⚠️ 'products' array NOT found!")
                        }
                        
                        // 检查 subscriptionGroups
                        if let subscriptionGroups = json["subscriptionGroups"] as? [[String: Any]] {
                            print("[StoreKitManager] ✅ 'subscriptionGroups' found, count: \(subscriptionGroups.count)")
                            for (index, group) in subscriptionGroups.enumerated() {
                                print("[StoreKitManager]   Group \(index):")
                                if let name = group["name"] as? String {
                                    print("[StoreKitManager]     Name: \(name)")
                                }
                                if let subscriptions = group["subscriptions"] as? [[String: Any]] {
                                    print("[StoreKitManager]     Subscriptions count: \(subscriptions.count)")
                                    for subscription in subscriptions {
                                        if let productID = subscription["productID"] as? String {
                                            print("[StoreKitManager]       - Product ID: \(productID)")
                                        }
                                    }
                                }
                            }
                        } else {
                            print("[StoreKitManager] ⚠️ 'subscriptionGroups' NOT found!")
                        }
                    } else {
                        print("[StoreKitManager] ❌ Failed to parse JSON")
                    }
                }
            } catch {
                print("[StoreKitManager] ❌ Failed to read file: \(error)")
            }
        } else {
            print("[StoreKitManager] ❌ Subscription.storekit NOT found in main bundle")
            // 列出 bundle 中的所有资源文件
            print("[StoreKitManager] Listing all resource files in bundle:")
            if let resourcePath = Bundle.main.resourcePath {
                let fileManager = FileManager.default
                if let files = try? fileManager.contentsOfDirectory(atPath: resourcePath) {
                    for file in files {
                        print("[StoreKitManager]   - \(file)")
                    }
                }
            }
        }
        
        print("[StoreKitManager] [4/4] Loading products from StoreKit...")
        do {
            let storeProducts = try await Product.products(for: productIDs)
            print("[StoreKitManager] ✅ Products loaded successfully, count: \(storeProducts.count)")
            for product in storeProducts {
                print("[StoreKitManager] Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
            }
            products = storeProducts.sorted { $0.price < $1.price }
            await updatePurchasedSubscriptions()
        } catch {
            self.error = error
            print("[StoreKitManager] ❌ Failed to load products: \(error)")
            print("[StoreKitManager] Error details: \(error.localizedDescription)")
            print("[StoreKitManager] Error type: \(type(of: error))")
        }
        
        print("[StoreKitManager] ========================================")
        print("[StoreKitManager] loadProducts completed")
        print("[StoreKitManager] ========================================")
        
        // 如果没有加载到产品，并且是 DEBUG 模式，添加一些模拟产品用于测试
        #if DEBUG
        if products.isEmpty {
            print("[StoreKitManager] No products loaded, using mock products for testing")
        }
        #endif
    }
    
    public func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await transaction.finish()
            await updatePurchasedSubscriptions()
            return transaction
            
        case .userCancelled:
            throw SubscriptionError.userCancelled
            
        case .pending:
            throw SubscriptionError.pending
            
        @unknown default:
            throw SubscriptionError.verificationFailed
        }
    }
    
    public func restorePurchases() async throws {
        try await AppStore.sync()
        await updatePurchasedSubscriptions()
    }
    
    private func updatePurchasedSubscriptions() async {
        var purchased: [Product] = []
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if let product = products.first(where: { $0.id == transaction.productID }) {
                    purchased.append(product)
                }
            }
        }
        
        purchasedSubscriptions = purchased
    }
    
    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let verificationError):
            throw verificationError
        }
    }
}
