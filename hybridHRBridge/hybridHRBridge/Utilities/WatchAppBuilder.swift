import Foundation

/// Utility for building and modifying .wapp files for Fossil Hybrid HR watches
/// Based on Fossil HR SDK pack.py structure
/// Source: https://github.com/dakhnod/Fossil-HR-SDK/blob/main/tools/pack.py
final class WatchAppBuilder {
    
    private let logger = LogManager.shared
    
    // MARK: - .wapp File Structure
    // File handle: 0xFE15 (APP_CODE in little-endian)
    // File version: 0x0003
    // File offset: 0x00000000
    // File size: 4 bytes (little-endian)
    // Content block:
    //   - Header (88 bytes): version + offsets
    //   - File sections: code, icons, layout, display_name, config
    // CRC32C: 4 bytes at end
    
    /// Build a .wapp file from components
    /// - Parameters:
    ///   - identifier: App identifier (e.g., "customTextApp")
    ///   - version: App version (e.g., "1.0.0.0")
    ///   - displayName: Display name shown on watch
    ///   - codeSnapshot: Compiled JerryScript snapshot data
    ///   - layoutFiles: Dictionary of layout filename to JSON string
    ///   - iconFiles: Dictionary of icon filename to compressed icon data
    /// - Returns: Complete .wapp file data
    func buildWatchApp(
        identifier: String,
        version: String,
        displayName: String,
        codeSnapshot: Data,
        layoutFiles: [String: String] = [:],
        iconFiles: [String: Data] = [:]
    ) throws -> Data {
        logger.info("WatchAppBuilder", "Building .wapp for '\(identifier)' v\(version)")
        
        var contentBlock = Data()
        
        // Parse version string (e.g., "1.0.0.0")
        let versionComponents = version.split(separator: ".").compactMap { UInt8($0) }
        guard versionComponents.count == 4 else {
            throw WatchAppBuilderError.invalidVersion
        }
        contentBlock.append(contentsOf: versionComponents)
        
        // Build file sections
        var allFiles: [(directory: String, filename: String, contents: Data, appendNull: Bool)] = []
        
        // Code section
        allFiles.append(("code", identifier, codeSnapshot, false))
        
        // Icons section
        for (filename, data) in iconFiles.sorted(by: { $0.key < $1.key }) {
            allFiles.append(("icons", filename, data, false))
        }
        
        // Layout section
        for (filename, jsonString) in layoutFiles.sorted(by: { $0.key < $1.key }) {
            var data = jsonString.data(using: .utf8) ?? Data()
            data.append(0) // Null terminator
            allFiles.append(("layout", filename, data, false))
        }
        
        // Display name section
        var displayNameData = displayName.data(using: .utf8) ?? Data()
        displayNameData.append(0) // Null terminator
        allFiles.append(("display_name", "display_name", displayNameData, false))
        
        // Config section (empty for now)
        // Can be used for future configuration
        
        // Calculate section sizes and offsets
        var directorySizes: [String: Int] = [:]
        for directory in ["code", "icons", "layout", "display_name", "config"] {
            var size = 0
            let filesInDir = allFiles.filter { $0.directory == directory }
            for file in filesInDir {
                // Each file: 1 byte (filename length + 1) + filename + 1 null byte + 2 bytes size + contents
                size += 1 + file.filename.utf8.count + 1 + 2 + file.contents.count
            }
            directorySizes[directory] = size
        }
        
        let offsetCode = 88
        let offsetIcons = offsetCode + (directorySizes["code"] ?? 0)
        let offsetLayout = offsetIcons + (directorySizes["icons"] ?? 0)
        let offsetDisplayName = offsetLayout + (directorySizes["layout"] ?? 0)
        let offsetConfig = offsetDisplayName + (directorySizes["display_name"] ?? 0)
        let offsetFileEnd = offsetConfig + (directorySizes["config"] ?? 0)
        
        // Write header (84 more bytes after version = 88 total)
        contentBlock.append(UInt32(0).littleEndianData)  // Reserved
        contentBlock.append(UInt32(0).littleEndianData)  // Reserved
        contentBlock.append(UInt32(offsetCode).littleEndianData)
        contentBlock.append(UInt32(offsetIcons).littleEndianData)
        contentBlock.append(UInt32(offsetLayout).littleEndianData)
        contentBlock.append(UInt32(offsetDisplayName).littleEndianData)
        contentBlock.append(UInt32(offsetDisplayName).littleEndianData)  // Duplicate in original
        contentBlock.append(UInt32(offsetConfig).littleEndianData)
        contentBlock.append(UInt32(offsetFileEnd).littleEndianData)
        
        // Padding (9 more UInt32s)
        for _ in 0..<9 {
            contentBlock.append(UInt32(0).littleEndianData)
        }
        
        // Write file sections in order
        let orderedDirectories = ["code", "icons", "layout", "display_name", "config"]
        for directory in orderedDirectories {
            let filesInDir = allFiles.filter { $0.directory == directory }.sorted { $0.filename < $1.filename }
            for file in filesInDir {
                // Filename length + 1 (for null terminator)
                let filenameLength = UInt8(file.filename.utf8.count + 1)
                contentBlock.append(filenameLength)
                
                // Filename
                contentBlock.append(file.filename.data(using: .utf8)!)
                
                // Null terminator
                contentBlock.append(0)
                
                // File size (2 bytes, little-endian)
                let size = UInt16(file.contents.count)
                contentBlock.append(size.littleEndianData)
                
                // File contents
                contentBlock.append(file.contents)
            }
        }
        
        // Build complete .wapp file
        var fullFile = Data()
        fullFile.append(contentsOf: [0xFE, 0x15])  // File handle (APP_CODE)
        fullFile.append(contentsOf: [0x03, 0x00])  // File version
        fullFile.append(UInt32(0).littleEndianData)  // File offset
        fullFile.append(UInt32(contentBlock.count).littleEndianData)  // File size
        fullFile.append(contentBlock)
        
        // Calculate and append CRC32C
        let crc = CRC32.checksumC(contentBlock)
        fullFile.append(crc.littleEndianData)
        
        logger.info("WatchAppBuilder", "Built .wapp file: \(fullFile.count) bytes")
        return fullFile
    }
    
    /// Modify an existing .wapp file's layout to update display text
    /// - Parameters:
    ///   - wappData: Original .wapp file data
    ///   - layoutName: Name of layout file to modify
    ///   - newText: New text to display
    /// - Returns: Modified .wapp file data
    func modifyLayoutText(in wappData: Data, layoutName: String, newText: String) throws -> Data {
        logger.info("WatchAppBuilder", "Modifying layout '\(layoutName)' with text: \(newText)")
        
        // Parse .wapp structure
        guard wappData.count >= 14 else {
            throw WatchAppBuilderError.invalidWappFile
        }
        
        // Verify file handle
        let fileHandle = UInt16(littleEndian: wappData.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt16.self) })
        guard fileHandle == 0x15FE else {
            throw WatchAppBuilderError.invalidWappFile
        }
        
        // Extract content block
        let fileSize = UInt32(littleEndian: wappData.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt32.self) })
        let contentStart = 14
        let contentEnd = contentStart + Int(fileSize)
        
        guard wappData.count >= contentEnd + 4 else {
            throw WatchAppBuilderError.invalidWappFile
        }
        
        var contentBlock = wappData.subdata(in: contentStart..<contentEnd)
        
        // Parse header to find layout section
        guard contentBlock.count >= 88 else {
            throw WatchAppBuilderError.invalidWappFile
        }
        
        let offsetLayout = Int(UInt32(littleEndian: contentBlock.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt32.self) }))
        let offsetDisplayName = Int(UInt32(littleEndian: contentBlock.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) }))
        
        // Find and modify the layout file
        var currentOffset = offsetLayout
        var modified = false
        
        while currentOffset < offsetDisplayName && currentOffset < contentBlock.count {
            let filenameLength = Int(contentBlock[currentOffset])
            currentOffset += 1
            
            guard currentOffset + filenameLength <= contentBlock.count else { break }
            
            let filenameData = contentBlock.subdata(in: currentOffset..<(currentOffset + filenameLength - 1))
            let filename = String(data: filenameData, encoding: .utf8) ?? ""
            currentOffset += filenameLength
            
            let fileSize = Int(UInt16(littleEndian: contentBlock.withUnsafeBytes { $0.load(fromByteOffset: currentOffset, as: UInt16.self) }))
            currentOffset += 2
            
            if filename == layoutName {
                // Found the layout file - modify it
                let layoutData = contentBlock.subdata(in: currentOffset..<(currentOffset + fileSize))
                if var layoutJSON = String(data: layoutData, encoding: .utf8) {
                    // Remove null terminator if present
                    if layoutJSON.hasSuffix("\0") {
                        layoutJSON.removeLast()
                    }
                    
                    // Parse and modify JSON
                    if var json = try? JSONSerialization.jsonObject(with: layoutJSON.data(using: .utf8)!, options: []) as? [String: Any] {
                        // Update text field
                        json["text"] = newText
                        
                        // Re-serialize
                        let newLayoutData = try JSONSerialization.data(withJSONObject: json, options: [])
                        var newLayoutString = String(data: newLayoutData, encoding: .utf8)!
                        newLayoutString.append("\0")  // Re-add null terminator
                        
                        let newLayoutBytes = newLayoutString.data(using: .utf8)!
                        
                        // Replace in content block
                        contentBlock.replaceSubrange(currentOffset..<(currentOffset + fileSize), with: newLayoutBytes)
                        
                        modified = true
                        logger.info("WatchAppBuilder", "Modified layout '\(layoutName)'")
                        break
                    }
                }
            }
            
            currentOffset += fileSize
        }
        
        if !modified {
            logger.warning("WatchAppBuilder", "Could not find or modify layout '\(layoutName)'")
        }
        
        // Rebuild .wapp file with modified content
        var fullFile = wappData.subdata(in: 0..<contentStart)
        
        // Update file size
        var fileSizeBytes = UInt32(contentBlock.count).littleEndianData
        fullFile.replaceSubrange(10..<14, with: fileSizeBytes)
        
        // Append modified content
        fullFile.append(contentBlock)
        
        // Recalculate and append CRC32C
        let crc = CRC32.checksumC(contentBlock)
        fullFile.append(crc.littleEndianData)
        
        return fullFile
    }
}

// MARK: - Errors

enum WatchAppBuilderError: Error, LocalizedError {
    case invalidVersion
    case invalidWappFile
    case layoutNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            return "Invalid version format. Expected format: X.Y.Z.W"
        case .invalidWappFile:
            return "Invalid .wapp file format"
        case .layoutNotFound:
            return "Layout file not found in .wapp"
        }
    }
}

// MARK: - Helpers

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
