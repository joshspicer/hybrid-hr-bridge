import Foundation
import CoreBluetooth
import Combine

/// Manages music control commands and info updates
/// Sources:
/// - MusicControlRequest.java (commands)
/// - MusicInfoSetRequest.java (track info)
@MainActor
final class MusicControlManager: ObservableObject {
    
    // MARK: - Types
    
    enum MusicCommand: UInt8 {
        case playPause = 0x02
        case next = 0x03
        case previous = 0x04
        case volumeUp = 0x05
        case volumeDown = 0x06
    }
    
    struct MusicStateSpec {
        let artist: String
        let album: String
        let track: String
        let duration: Int // duration in seconds
        let trackCount: Int
        let trackNum: Int
        let isPlaying: Bool
    }

    // MARK: - Private Properties
    
    private let bluetoothManager: BluetoothManager
    private let fileTransferManager: FileTransferManager
    private let logger = LogManager.shared
    
    // MARK: - Initialization
    
    init(bluetoothManager: BluetoothManager, fileTransferManager: FileTransferManager) {
        self.bluetoothManager = bluetoothManager
        self.fileTransferManager = fileTransferManager
    }
    
    // MARK: - Public API
    
    /// Send a music control command to the watch
    func sendCommand(_ command: MusicCommand) async throws {
        // Structure from MusicControlRequest.java:
        // [0x02, 0x05, commandByte, 0x00]
        
        let payload = Data([0x02, 0x05, command.rawValue, 0x00])
        
        logger.info("Music", "Sending command: \(command) (0x\(String(format: "%02X", command.rawValue)))")
        
        try await bluetoothManager.write(
            data: payload,
            to: FossilConstants.characteristicEvents
        )
    }
    
    /// Update music track information on the watch
    /// Source: MusicInfoSetRequest.java
    func updateMusicInfo(artist: String, album: String, title: String) async throws {
        logger.info("Music", "Updating info: \(title) by \(artist)")
        
        let fileData = createMusicInfoFile(artist: artist, album: album, title: title)
        
        // Upload to MUSIC_INFO handle (0x0400)
        // Note: Music info updates do NOT require encryption/auth wrapper usually,
        // but let's check if we need to set requiresAuth based on observation.
        // Gadgetbridge uses generic FilePutRequest for this, which is NOT encrypted.
        try await fileTransferManager.putFile(fileData, to: .musicInfo, requiresAuth: false)
    }
    
    // MARK: - Helpers
    
    /// Construct the binary payload for music info
    /// Source: MusicInfoSetRequest.java#createFile
    private func createMusicInfoFile(artist: String, album: String, title: String) -> Data {
        // Strings + null terminators
        let titleData = title.data(using: .utf8) ?? Data()
        let artistData = artist.data(using: .utf8) ?? Data()
        let albumData = album.data(using: .utf8) ?? Data()
        
        let titleLen = titleData.count + 1
        let artistLen = artistData.count + 1
        let albumLen = albumData.count + 1
        
        // Header length is 8 bytes
        // Total length = Header(8) + Strings
        let totalLength = 8 + titleLen + artistLen + albumLen
        
        var data = Data()
        
        // 1. Total Length (UInt16 Little Endian)
        withUnsafeBytes(of: UInt16(totalLength).littleEndian) { data.append(contentsOf: $0) }
        
        // 2. 0x01 (Unknown, maybe version or type)
        data.append(0x01)
        
        // 3. Lengths
        data.append(UInt8(titleLen))
        data.append(UInt8(artistLen))
        data.append(UInt8(albumLen))
        
        // 4. 0x0C (Unknown)
        data.append(0x0C)
        
        // 5. 0x00 (Unknown)
        data.append(0x00)
        
        // 6. Strings with null terminators
        data.append(titleData)
        data.append(0x00)
        
        data.append(artistData)
        data.append(0x00)
        
        data.append(albumData)
        data.append(0x00)
        
        return data
    }
}
