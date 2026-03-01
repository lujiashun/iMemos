//
//  ImageCompressor.swift
//  MoeMemos
//
//  Created by AI Assistant on 2026/3/1.
//

import UIKit
import ImageIO
import MobileCoreServices

/// 图片压缩配置
struct ImageCompressionConfig {
    /// 目标文件大小（字节），默认 300KB
    let targetSize: Int
    /// 最低质量要求（0-1），默认 0.85
    let minQuality: CGFloat
    /// 最大尺寸（长边），默认 2048 像素
    let maxDimension: CGFloat
    
    static let `default` = ImageCompressionConfig(
        targetSize: 300 * 1024,  // 300KB
        minQuality: 0.85,         // 85%
        maxDimension: 2048       // 2K 分辨率
    )
}

/// 图片压缩结果
enum ImageCompressionResult {
    /// 压缩成功，包含压缩后的数据和实际质量
    case success(data: Data, quality: CGFloat, originalSize: Int, compressedSize: Int)
    /// 不需要压缩（原图已满足条件）
    case noNeed(data: Data, originalSize: Int)
    /// 压缩失败
    case failure(Error)
}

/// 图片压缩器
/// 核心策略：先降分辨率（保持比例），再调 JPEG 质量，闭环验证
enum ImageCompressor {
    
    /// 智能压缩图片
    /// - Parameters:
    ///   - image: 原始图片
    ///   - config: 压缩配置
    /// - Returns: 压缩结果
    static func compress(image: UIImage, config: ImageCompressionConfig = .default) -> ImageCompressionResult {
        guard let originalData = image.jpegData(compressionQuality: 1.0) else {
            return .failure(ImageCompressionError.invalidImage)
        }
        
        let originalSize = originalData.count
        
        // 1. 大小检测：如果原图已经小于目标大小，直接返回
        if originalSize <= config.targetSize {
            return .noNeed(data: originalData, originalSize: originalSize)
        }
        
        // 2. 先限制最大分辨率（保持比例）
        let resizedImage = resizeImageIfNeeded(image, maxDimension: config.maxDimension)
        
        // 3. 二分查找最佳压缩质量
        guard let compressedData = findOptimalQuality(
            image: resizedImage,
            targetSize: config.targetSize,
            minQuality: config.minQuality
        ) else {
            return .failure(ImageCompressionError.compressionFailed)
        }
        
        let compressedSize = compressedData.count
        let actualQuality = calculateActualQuality(originalSize: originalSize, compressedSize: compressedSize, minQuality: config.minQuality)
        
        return .success(
            data: compressedData,
            quality: actualQuality,
            originalSize: originalSize,
            compressedSize: compressedSize
        )
    }
    
    /// 异步压缩图片（用于大图片避免阻塞主线程）
    static func compressAsync(image: UIImage, config: ImageCompressionConfig = .default) async -> ImageCompressionResult {
        await Task.detached(priority: .userInitiated) {
            compress(image: image, config: config)
        }.value
    }
    
    // MARK: - Private Methods
    
    /// 调整图片分辨率（保持比例）
    private static func resizeImageIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let currentWidth = image.size.width
        let currentHeight = image.size.height
        let currentMaxDimension = max(currentWidth, currentHeight)
        
        // 如果长边已经小于等于限制，不需要调整
        guard currentMaxDimension > maxDimension else {
            return image
        }
        
        // 计算缩放比例（保持宽高比）
        let scale = maxDimension / currentMaxDimension
        let newWidth = currentWidth * scale
        let newHeight = currentHeight * scale
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        // 使用高质量插值渲染
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
            return image
        }
        
        return resizedImage
    }
    
    /// 二分查找最佳压缩质量
    /// 策略：优先满足大小要求，同时保证质量不低于 minQuality
    private static func findOptimalQuality(image: UIImage, targetSize: Int, minQuality: CGFloat) -> Data? {
        var low: CGFloat = minQuality  // 最低质量限制
        var high: CGFloat = 1.0        // 最高质量
        var bestData: Data?
        var bestQuality: CGFloat = 0
        
        // 二分查找，最多 10 次迭代确保精度
        for _ in 0..<10 {
            let mid = (low + high) / 2
            
            guard let data = image.jpegData(compressionQuality: mid) else {
                continue
            }
            
            // 如果当前质量满足大小要求，尝试更高质量
            if data.count <= targetSize {
                bestData = data
                bestQuality = mid
                low = mid  // 尝试更高质量
            } else {
                high = mid  // 需要降低质量
            }
            
            // 如果已经找到满足条件的最佳质量，提前退出
            if high - low < 0.01 && bestData != nil {
                break
            }
        }
        
        // 如果二分查找没找到满足条件的，使用最低质量再试一次
        if bestData == nil {
            bestData = image.jpegData(compressionQuality: minQuality)
        }
        
        return bestData
    }
    
    /// 估算实际压缩质量（基于文件大小比例）
    private static func calculateActualQuality(originalSize: Int, compressedSize: Int, minQuality: CGFloat) -> CGFloat {
        // 质量估算公式：基于压缩后的文件大小比例
        let ratio = CGFloat(compressedSize) / CGFloat(originalSize)
        // 线性映射到质量范围 [minQuality, 1.0]
        let estimatedQuality = minQuality + (1.0 - minQuality) * (1.0 - ratio)
        return max(minQuality, min(1.0, estimatedQuality))
    }
}

// MARK: - Errors

enum ImageCompressionError: Error, LocalizedError {
    case invalidImage
    case compressionFailed
    case sizeExceedsLimit
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "无效的图片数据"
        case .compressionFailed:
            return "图片压缩失败"
        case .sizeExceedsLimit:
            return "图片大小超过限制且无法压缩到目标大小"
        }
    }
}

// MARK: - Convenience Extensions

extension UIImage {
    /// 快速压缩到指定大小
    func compressed(to targetSize: Int = 300 * 1024, minQuality: CGFloat = 0.85) -> Data? {
        let result = ImageCompressor.compress(
            image: self,
            config: ImageCompressionConfig(
                targetSize: targetSize,
                minQuality: minQuality,
                maxDimension: 2048
            )
        )
        
        switch result {
        case .success(let data, _, _, _):
            return data
        case .noNeed(let data, _):
            return data
        case .failure:
            return nil
        }
    }
    
    /// 获取图片文件大小（JPEG 质量 1.0）
    var fileSize: Int {
        jpegData(compressionQuality: 1.0)?.count ?? 0
    }
    
    /// 格式化文件大小显示
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}
