import Foundation
import UIKit

/// Configuration for notification filters and icons
/// Source: NotificationHRConfiguration.java and NotificationFilterPutHRRequest.java
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/.../NotificationHRConfiguration.java
struct NotificationConfiguration {
    let packageName: String
    let iconName: String
    let packageCrc: Data
    
    /// Create configuration with automatic CRC calculation
    /// Source: NotificationHRConfiguration.java#L29-L41
    init(packageName: String, iconName: String) {
        self.packageName = packageName
        self.iconName = iconName
        self.packageCrc = CRC32.calculateLittleEndian(data: packageName.data(using: .utf8)!)
    }
    
    /// Create configuration with explicit CRC (used for hardcoded "call" CRC)
    /// Source: NotificationHRConfiguration.java#L43-L47
    init(packageName: String, packageCrc: Data, iconName: String) {
        self.packageName = packageName
        self.packageCrc = packageCrc
        self.iconName = iconName
    }
    
    // MARK: - Standard Configurations
    
    /// Generic fallback notification configuration
    /// Source: FossilHRWatchAdapter.java#L608
    static var generic: NotificationConfiguration {
        NotificationConfiguration(packageName: "generic", iconName: "general_white.bin")
    }
    
    /// Call notification configuration with hardcoded CRC
    /// Source: FossilHRWatchAdapter.java#L609
    /// The call CRC is hardcoded in Gadgetbridge, not computed
    static var call: NotificationConfiguration {
        // Hardcoded call CRC from PlayCallNotificationRequest.java
        // ByteBuffer.wrap(new byte[]{(byte) 0x80, (byte) 0x00, (byte) 0x59, (byte) 0xB7})
        let callCrc = Data([0x80, 0x00, 0x59, 0xB7])
        return NotificationConfiguration(
            packageName: "call",
            packageCrc: callCrc,
            iconName: "icIncomingCall.icon"
        )
    }
    
    // MARK: - Filter File Generation
    
    /// Build notification filter file for upload to watch
    /// Source: NotificationFilterPutHRRequest.java#L39-L116
    static func buildFilterFile(configurations: [NotificationConfiguration]) -> Data {
        var buffer = Data()
        
        for config in configurations {
            // Calculate payload length for this config
            var payloadLength = config.iconName.isEmpty ? 12 : (config.iconName.count + 18)
            
            // Call notifications need extra space for multi-icon format
            if config.packageName == "call" {
                payloadLength += 44
            }
            
            // Write entry length (2 bytes, little-endian)
            buffer.append(UInt8(payloadLength & 0xFF))
            buffer.append(UInt8((payloadLength >> 8) & 0xFF))
            
            // Package CRC (6 bytes total)
            buffer.append(PacketID.packageNameCrc.rawValue)  // 0x04
            buffer.append(0x04)  // CRC length
            buffer.append(config.packageCrc)  // 4 bytes CRC
            
            // Group ID (3 bytes)
            buffer.append(PacketID.groupId.rawValue)  // 0x80
            buffer.append(0x01)
            buffer.append(0x00)
            
            // Priority (3 bytes)
            buffer.append(PacketID.priority.rawValue)  // 0xC1
            buffer.append(0x01)
            buffer.append(0xFF)  // Highest priority
            
            // Icon configuration
            if config.packageName == "call" {
                // Multi-icon format for call notifications
                // Source: NotificationFilterPutHRRequest.java#L84-L102
                let icon1 = "icIncomingCall.icon"
                let icon2 = "icMissedCall.icon"
                
                buffer.append(PacketID.icon.rawValue)  // 0x82
                buffer.append(UInt8(icon1.count + 4))
                buffer.append(0x02)
                buffer.append(0x00)
                buffer.append(UInt8(icon1.count + 1))
                buffer.append(contentsOf: icon1.utf8)
                buffer.append(0x00)
                
                buffer.append(0x40)
                buffer.append(0x00)
                buffer.append(UInt8(icon2.count + 1))
                buffer.append(contentsOf: icon2.utf8)
                buffer.append(0x00)
                
                buffer.append(0xBD)
                buffer.append(0x00)
                buffer.append(UInt8(icon1.count + 1))
                buffer.append(contentsOf: icon1.utf8)
                buffer.append(0x00)
            } else if !config.iconName.isEmpty {
                // Single icon format
                // Source: NotificationFilterPutHRRequest.java#L103-L112
                buffer.append(PacketID.icon.rawValue)  // 0x82
                buffer.append(UInt8(config.iconName.count + 4))
                buffer.append(0xFF)  // Mask for all notification types
                buffer.append(0x00)
                buffer.append(UInt8(config.iconName.count + 1))
                buffer.append(contentsOf: config.iconName.utf8)
                buffer.append(0x00)
            }
        }
        
        return buffer
    }
    
    // MARK: - Packet IDs
    
    /// Packet identifier bytes for notification filter structure
    /// Source: NotificationFilterPutHRRequest.java#L118-L134
    private enum PacketID: UInt8 {
        case packageName = 0x01
        case senderName = 0x02
        case packageNameCrc = 0x04
        case groupId = 0x80
        case appDisplayName = 0x81
        case icon = 0x82
        case priority = 0xC1
        case movement = 0xC2
        case vibration = 0xC3
    }
}

// MARK: - Notification Icon

/// Represents a notification icon with RLE-encoded image data
/// Source: NotificationImage.java
/// https://codeberg.org/Freeyourgadget/Gadgetbridge/.../NotificationImage.java
struct NotificationIcon {
    static let maxWidth = 24
    static let maxHeight = 24
    
    let fileName: String
    let width: Int
    let height: Int
    let imageData: Data
    
    /// Create icon from UIImage
    /// Source: NotificationImage.java#L40-L44
    init(fileName: String, image: UIImage) {
        self.fileName = fileName
        
        // Scale image to max dimensions
        let scaledImage = image.scaled(toMaxWidth: Self.maxWidth, maxHeight: Self.maxHeight)
        self.width = Int(scaledImage.size.width)
        self.height = Int(scaledImage.size.height)
        
        // Convert to 2-bit grayscale with alpha and RLE encode
        self.imageData = Self.encodeImage(scaledImage)
    }
    
    /// Create icon from pre-encoded data
    init(fileName: String, imageData: Data, width: Int, height: Int) {
        self.fileName = fileName
        self.imageData = imageData
        self.width = min(width, Self.maxWidth)
        self.height = min(height, Self.maxHeight)
    }
    
    // MARK: - Image Encoding
    
    /// Convert UIImage to RLE-encoded 2-bit grayscale with alpha
    /// Source: ImageConverter.java#L38-L52 and RLEEncoder.java#L22-L49
    private static func encodeImage(_ image: UIImage) -> Data {
        guard let cgImage = image.cgImage else {
            return Data()
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Convert RGBA pixels to 2-bit grayscale + 2-bit alpha
        // Source: ImageConverter.java#L42-L49
        var encodedPixels = [UInt8]()
        for i in stride(from: 0, to: totalBytes, by: 4) {
            let r = Int(pixelData[i])
            let g = Int(pixelData[i + 1])
            let b = Int(pixelData[i + 2])
            let a = Int(pixelData[i + 3])
            
            // Convert to grayscale (average of RGB)
            let gray = (r + g + b) / 3
            let grayValue = UInt8((gray >> 6) & 0b11)  // Top 2 bits -> 0-3
            
            // Alpha (inverted and shifted)
            let alphaValue = UInt8((~a >> 4) & 0b1100)
            
            encodedPixels.append(grayValue | alphaValue)
        }
        
        // RLE encode the pixel data
        return rleEncode(encodedPixels)
    }
    
    /// RLE encode a byte array
    /// Source: RLEEncoder.java#L22-L49
    private static func rleEncode(_ data: [UInt8]) -> Data {
        guard !data.isEmpty else { return Data() }
        
        var result = Data()
        var lastByte = data[0]
        var count: UInt8 = 1
        
        for i in 1..<data.count {
            let currentByte = data[i]
            
            if currentByte != lastByte || count >= 255 {
                result.append(count)
                result.append(lastByte)
                count = 1
                lastByte = currentByte
            } else {
                count += 1
            }
        }
        
        // Write final run
        result.append(count)
        result.append(data.last!)
        
        return result
    }
    
    // MARK: - File Format
    
    /// Encode icon for upload to file handle 0x0701
    /// Source: NotificationImagePutRequest.java#L42-L56
    func encodeForUpload() -> Data {
        var data = Data()
        
        // Filename as null-terminated string
        let filenameData = fileName.data(using: .utf8)!
        let entrySize = filenameData.count + 1 + 1 + 1 + imageData.count + 2
        
        // Entry size (2 bytes, little-endian)
        data.append(UInt8(entrySize & 0xFF))
        data.append(UInt8((entrySize >> 8) & 0xFF))
        
        // Filename with null terminator
        data.append(filenameData)
        data.append(0x00)
        
        // Width and height
        data.append(UInt8(width))
        data.append(UInt8(height))
        
        // RLE-encoded image data
        data.append(imageData)
        
        // Terminator
        data.append(contentsOf: [0xFF, 0xFF])
        
        return data
    }
    
    /// Build file with multiple icons for upload
    /// Source: NotificationImagePutRequest.java
    static func buildIconFile(icons: [NotificationIcon]) -> Data {
        var data = Data()
        for icon in icons {
            data.append(icon.encodeForUpload())
        }
        return data
    }
    
    // MARK: - Standard Icons
    
    /// Create standard notification icons
    /// Source: FossilHRWatchAdapter.java#L600-L604
    static func standardIcons() -> [NotificationIcon] {
        var icons: [NotificationIcon] = []
        
        // Generic white icon (alert circle)
        if let image = createSimpleIcon(size: CGSize(width: 24, height: 24), symbol: "●") {
            icons.append(NotificationIcon(fileName: "general_white.bin", image: image))
        }
        
        // Incoming call icon (phone)
        if let image = UIImage(systemName: "phone")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            icons.append(NotificationIcon(fileName: "icIncomingCall.icon", image: image))
        }
        
        // Missed call icon (phone with badge)
        if let image = UIImage(systemName: "phone.badge.xmark")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            icons.append(NotificationIcon(fileName: "icMissedCall.icon", image: image))
        }
        
        // Message icon
        if let image = UIImage(systemName: "message")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            icons.append(NotificationIcon(fileName: "icMessage.icon", image: image))
        }
        
        return icons
    }
    
    /// Create a simple icon with a symbol
    private static func createSimpleIcon(size: CGSize, symbol: String) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Draw white background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw symbol in center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.height * 0.7),
                .foregroundColor: UIColor.black
            ]
            let text = symbol as NSString
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}

// MARK: - UIImage Extension

extension UIImage {
    /// Scale image to fit within max dimensions while preserving aspect ratio
    /// Source: NotificationImage.java#L41 (calls BitmapUtil.scaleWithMax)
    func scaled(toMaxWidth maxWidth: Int, maxHeight: Int) -> UIImage {
        let currentWidth = Int(size.width)
        let currentHeight = Int(size.height)
        
        if currentWidth <= maxWidth && currentHeight <= maxHeight {
            return self
        }
        
        let widthRatio = CGFloat(maxWidth) / CGFloat(currentWidth)
        let heightRatio = CGFloat(maxHeight) / CGFloat(currentHeight)
        let scaleFactor = min(widthRatio, heightRatio)
        
        let newSize = CGSize(
            width: CGFloat(currentWidth) * scaleFactor,
            height: CGFloat(currentHeight) * scaleFactor
        )
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
