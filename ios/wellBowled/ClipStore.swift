import AVFoundation
import Foundation
import Photos
import UIKit
import os

private let log = Logger(subsystem: "com.wellbowled", category: "ClipStore")

/// A saved clip — either a release-to-end segment or a full session recording.
struct SavedClip: Identifiable, Codable {
    let id: UUID
    let deliveryID: UUID?
    let createdAt: Date
    let clipFileName: String          // filename in Documents/clips/
    let thumbnailFileName: String?    // filename in Documents/clips/thumbs/
    let durationSeconds: Double
    let kind: ClipKind
    let deliverySequence: Int?
    let speedKph: Double?

    enum ClipKind: String, Codable {
        case releaseToEnd   // trimmed: release → hit/end
        case fullSession    // full session recording
    }

    var clipURL: URL {
        ClipStore.clipsDirectory.appendingPathComponent(clipFileName)
    }

    var thumbnailURL: URL? {
        guard let thumbnailFileName else { return nil }
        return ClipStore.thumbsDirectory.appendingPathComponent(thumbnailFileName)
    }
}

/// Persists saved clips to Documents/clips/ with a JSON index.
final class ClipStore {

    static let shared = ClipStore()

    static var clipsDirectory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var thumbsDirectory: URL {
        let url = clipsDirectory.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var indexURL: URL {
        Self.clipsDirectory.appendingPathComponent("clips_index.json")
    }

    // MARK: - CRUD

    func loadAll() -> [SavedClip] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([SavedClip].self, from: data)
        } catch {
            log.error("Failed to load clips index: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ clips: [SavedClip]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(clips)
            try data.write(to: indexURL)
        } catch {
            log.error("Failed to save clips index: \(error.localizedDescription, privacy: .public)")
        }
    }

    func append(_ clip: SavedClip) {
        var all = loadAll()
        all.insert(clip, at: 0)
        save(all)
    }

    func delete(_ clipID: UUID) {
        var all = loadAll()
        guard let idx = all.firstIndex(where: { $0.id == clipID }) else { return }
        let clip = all[idx]
        // Remove files
        try? FileManager.default.removeItem(at: clip.clipURL)
        if let thumbURL = clip.thumbnailURL {
            try? FileManager.default.removeItem(at: thumbURL)
        }
        all.remove(at: idx)
        save(all)
    }

    // MARK: - Save operations

    /// Save a delivery clip (release-to-end trim) to local storage and Photos.
    func saveDeliveryClip(
        from recordingURL: URL,
        delivery: Delivery,
        preRoll: Double = 0.5,
        postRoll: Double = 2.0
    ) async throws -> SavedClip {
        // Use releaseTimestamp if available, otherwise delivery timestamp
        let clipTimestamp = delivery.releaseTimestamp ?? delivery.timestamp

        let clipID = UUID()
        let fileName = "clip_\(clipID.uuidString).mp4"
        let destURL = Self.clipsDirectory.appendingPathComponent(fileName)

        // Extract the clip
        let asset = AVURLAsset(url: recordingURL)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let trackTimeRange = try await tracks.first?.load(.timeRange)
        let assetStart = CMTimeGetSeconds(trackTimeRange?.start ?? .zero)
        let assetEnd = assetStart + CMTimeGetSeconds(duration)

        let seekTime = clipTimestamp + assetStart
        let startTime = max(assetStart, seekTime - preRoll)
        let endTime = min(assetEnd, seekTime + postRoll)

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ClipError.exportSessionCreationFailed
        }

        exportSession.outputURL = destURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? ClipError.exportFailed
        }

        let clipDuration = endTime - startTime

        // Generate thumbnail
        let thumbFileName = try? await generateThumbnail(for: destURL, clipID: clipID)

        // Save to Photos
        await saveToPhotosLibrary(destURL)

        let clip = SavedClip(
            id: clipID,
            deliveryID: delivery.id,
            createdAt: Date(),
            clipFileName: fileName,
            thumbnailFileName: thumbFileName,
            durationSeconds: clipDuration,
            kind: .releaseToEnd,
            deliverySequence: delivery.sequence,
            speedKph: delivery.speedKph
        )
        append(clip)
        log.debug("Saved delivery clip: \(fileName) (\(clipDuration, privacy: .public)s)")
        return clip
    }

    /// Save the full session recording to local storage and Photos.
    func saveFullSession(
        from recordingURL: URL,
        delivery: Delivery?
    ) async throws -> SavedClip {
        let clipID = UUID()
        let fileName = "full_\(clipID.uuidString).mp4"
        let destURL = Self.clipsDirectory.appendingPathComponent(fileName)

        try FileManager.default.copyItem(at: recordingURL, to: destURL)

        let asset = AVURLAsset(url: destURL)
        let duration = try await asset.load(.duration)
        let durationSec = CMTimeGetSeconds(duration)

        let thumbFileName = try? await generateThumbnail(for: destURL, clipID: clipID)

        await saveToPhotosLibrary(destURL)

        let clip = SavedClip(
            id: clipID,
            deliveryID: delivery?.id,
            createdAt: Date(),
            clipFileName: fileName,
            thumbnailFileName: thumbFileName,
            durationSeconds: durationSec,
            kind: .fullSession,
            deliverySequence: delivery?.sequence,
            speedKph: delivery?.speedKph
        )
        append(clip)
        log.debug("Saved full session: \(fileName) (\(durationSec, privacy: .public)s)")
        return clip
    }

    // MARK: - Helpers

    private func generateThumbnail(for videoURL: URL, clipID: UUID) async throws -> String {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 400, height: 400)

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let (cgImage, _) = try await generator.image(at: time)
        let image = UIImage(cgImage: cgImage)

        let thumbName = "\(clipID.uuidString).jpg"
        let thumbURL = Self.thumbsDirectory.appendingPathComponent(thumbName)
        if let data = image.jpegData(compressionQuality: 0.7) {
            try data.write(to: thumbURL)
        }
        return thumbName
    }

    private func saveToPhotosLibrary(_ url: URL) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var authorized = status == .authorized || status == .limited
        if !authorized {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            authorized = newStatus == .authorized || newStatus == .limited
        }
        guard authorized else {
            log.warning("Photo Library access denied — clip saved locally only")
            return
        }
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { ok, err in
                    if ok { cont.resume() }
                    else { cont.resume(throwing: err ?? ClipError.exportFailed) }
                }
            }
            log.debug("Clip saved to Photos: \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Failed to save clip to Photos: \(error.localizedDescription, privacy: .public)")
        }
    }
}
