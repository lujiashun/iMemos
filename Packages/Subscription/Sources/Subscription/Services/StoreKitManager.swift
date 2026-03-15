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
    
    /// 当订阅状态发生变化时的回调（用于通知后端同步）
    public var onSubscriptionChanged: ((SubscriptionChange) -> Void)?
    
    public struct SubscriptionChange {
        public let isVip: Bool
        public let productId: String?
        public let expiresDate: Date?
        public let changeType: ChangeType
        
        public enum ChangeType {
            case purchase    // 新购买
            case refund      // 退款
            case restore     // 恢复购买
            case expiration  // 过期
        }
    }
    
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
        print("[StoreKitManager] Requesting products with IDs: \(productIDs)")
        print("[StoreKitManager] Current bundle identifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("[StoreKitManager] Is running in simulator: \(ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil)")
        
        do {
            print("[StoreKitManager] Calling Product.products(for:)...")
            let storeProducts = try await Product.products(for: productIDs)
            print("[StoreKitManager] ✅ Product.products(for:) returned, count: \(storeProducts.count)")
            
            if storeProducts.isEmpty {
                print("[StoreKitManager] ⚠️ WARNING: Product array is empty!")
                print("[StoreKitManager] This usually means:")
                print("[StoreKitManager]   1. StoreKit Configuration file is not set in Xcode Scheme")
                print("[StoreKitManager]   2. Product IDs in code don't match the .storekit file")
                print("[StoreKitManager]   3. .storekit file format is incorrect")
                print("[StoreKitManager] ")
                print("[StoreKitManager] To fix this:")
                print("[StoreKitManager]   1. In Xcode, select Product > Scheme > Edit Scheme")
                print("[StoreKitManager]   2. Select 'Run' > 'Options'")
                print("[StoreKitManager]   3. Under 'StoreKit Configuration', select 'Subscription.storekit'")
                print("[StoreKitManager]   4. Clean build folder and rebuild")
            } else {
                for product in storeProducts {
                    print("[StoreKitManager] Product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
                }
            }
            
            products = storeProducts.sorted { $0.price < $1.price }
            await updatePurchasedSubscriptions()
        } catch {
            self.error = error
            print("[StoreKitManager] ❌ Failed to load products: \(error)")
            print("[StoreKitManager] Error details: \(error.localizedDescription)")
            print("[StoreKitManager] Error type: \(type(of: error))")
            
            // 检查是否是特定的 StoreKit 错误
            let nsError = error as NSError
            print("[StoreKitManager] NSError domain: \(nsError.domain)")
            print("[StoreKitManager] NSError code: \(nsError.code)")
            print("[StoreKitManager] NSError userInfo: \(nsError.userInfo)")
        }
        
        print("[StoreKitManager] ========================================")
        print("[StoreKitManager] loadProducts completed")
        print("[StoreKitManager] ========================================")
        
        // 如果没有加载到产品，并且是 DEBUG 模式，从 .storekit 文件解析模拟产品
        #if DEBUG
        if products.isEmpty {
            print("[StoreKitManager] No products loaded from StoreKit, parsing from .storekit file...")
            await loadMockProductsFromStoreKitFile()
        }
        #endif
    }
    
    #if DEBUG
    /// 从 Subscription.storekit 文件加载模拟产品（用于真机 DEBUG 测试）
    private func loadMockProductsFromStoreKitFile() async {
        print("[StoreKitManager] Loading mock products from .storekit file...")
        
        guard let storeKitURL = Bundle.main.url(forResource: "Subscription", withExtension: "storekit") else {
            print("[StoreKitManager] ❌ Subscription.storekit not found")
            return
        }
        
        do {
            let fileContent = try String(contentsOf: storeKitURL, encoding: .utf8)
            guard let jsonData = fileContent.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                print("[StoreKitManager] ❌ Failed to parse JSON")
                return
            }
            
            // 从 products 数组创建模拟产品
            var mockProducts: [MockProduct] = []
            
            if let productsArray = json["products"] as? [[String: Any]] {
                for productDict in productsArray {
                    guard let productID = productDict["productID"] as? String,
                          let displayName = (productDict["localizations"] as? [[String: Any]])?.first?["displayName"] as? String,
                          let description = (productDict["localizations"] as? [[String: Any]])?.first?["description"] as? String,
                          let displayPrice = productDict["displayPrice"] as? String else {
                        continue
                    }
                    
                    let mockProduct = MockProduct(
                        id: productID,
                        displayName: displayName,
                        description: description,
                        displayPrice: displayPrice,
                        price: Decimal(string: displayPrice) ?? 0
                    )
                    mockProducts.append(mockProduct)
                    print("[StoreKitManager] Created mock product: \(productID) - \(displayName) - \(displayPrice)")
                }
            }
            
            // 从 subscriptionGroups 中读取订阅信息
            if let subscriptionGroups = json["subscriptionGroups"] as? [[String: Any]] {
                for group in subscriptionGroups {
                    if let subscriptions = group["subscriptions"] as? [[String: Any]] {
                        for subscription in subscriptions {
                            guard let productID = subscription["productID"] as? String else { continue }
                            
                            // 查找是否已存在
                            if !mockProducts.contains(where: { $0.id == productID }) {
                                let displayName = (subscription["localizations"] as? [[String: Any]])?.first?["displayName"] as? String ?? "Subscription"
                                let description = (subscription["localizations"] as? [[String: Any]])?.first?["description"] as? String ?? ""
                                let displayPrice = subscription["displayPrice"] as? String ?? "0.00"
                                
                                let mockProduct = MockProduct(
                                    id: productID,
                                    displayName: displayName,
                                    description: description,
                                    displayPrice: displayPrice,
                                    price: Decimal(string: displayPrice) ?? 0
                                )
                                mockProducts.append(mockProduct)
                                print("[StoreKitManager] Created mock product from subscription: \(productID) - \(displayName) - \(displayPrice)")
                            }
                        }
                    }
                }
            }
            
            // 保存模拟产品
            self.mockProducts = mockProducts
            print("[StoreKitManager] ✅ Loaded \(mockProducts.count) mock products from .storekit file")
            
        } catch {
            print("[StoreKitManager] ❌ Failed to load mock products: \(error)")
        }
    }
    
    /// 模拟产品数据结构
    public struct MockProduct: Identifiable, Sendable {
        public let id: String
        public let displayName: String
        public let description: String
        public let displayPrice: String
        public let price: Decimal
    }
    
    /// 模拟产品列表（用于 DEBUG 真机测试）
    @Published public private(set) var mockProducts: [MockProduct] = []
    #endif
    
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
        var latestTransaction: Transaction? = nil
        
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if let product = products.first(where: { $0.id == transaction.productID }) {
                    purchased.append(product)
                    // 保存最新的交易信息
                    if latestTransaction == nil || transaction.purchaseDate > latestTransaction!.purchaseDate {
                        latestTransaction = transaction
                    }
                }
            }
        }
        
        let previousCount = purchasedSubscriptions.count
        let wasVip = !purchasedSubscriptions.isEmpty
        let isVip = !purchased.isEmpty
        purchasedSubscriptions = purchased
        
        // 检测订阅状态变化并通知后端
        if previousCount != purchased.count || wasVip != isVip {
            let changeType: SubscriptionChange.ChangeType
            if purchased.count < previousCount {
                changeType = .refund
                print("[StoreKitManager] Subscription count decreased from \(previousCount) to \(purchased.count), may be due to refund")
            } else if purchased.count > previousCount {
                changeType = .purchase
                print("[StoreKitManager] Subscription count increased from \(previousCount) to \(purchased.count), new purchase")
            } else {
                changeType = .restore
                print("[StoreKitManager] Subscription restored or updated")
            }
            
            // 触发回调通知后端同步
            let change = SubscriptionChange(
                isVip: isVip,
                productId: latestTransaction?.productID,
                expiresDate: latestTransaction?.expirationDate,
                changeType: changeType
            )
            onSubscriptionChanged?(change)
        }
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
