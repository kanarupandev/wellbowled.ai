import AVFoundation
import Foundation
import Photos
import UIKit
import os

private let log = Logger(subsystem: "com.wellbowled.v2", category: "ClipStore")

struct SavedClip: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let clipFileName: String
    let thumbnailFileName: String?
    let durationSeconds: Double
    let kind: ClipKind
    let speedKMH: Double?
    let releaseFrame: Int?
    let arrivalFrame: Int?
    let releaseTimeInClip: Double?   // seconds into clip where release happens
    let arrivalTimeInClip: Double?   // seconds into clip where arrival happens

    enum ClipKind: String, Codable {
        case releaseToEnd
        case full
    }

    var clipURL: URL {
        ClipStore.clipsDir.appendingPathComponent(clipFileName)
    }

    var thumbnailURL: URL? {
        guard let thumbnailFileName else { return nil }
        return ClipStore.thumbsDir.appendingPathComponent(thumbnailFileName)
    }
}

final class ClipStore {
    static let shared = ClipStore()

    static var clipsDir: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clips")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var thumbsDir: URL {
        let url = clipsDir.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var indexURL: URL {
        Self.clipsDir.appendingPathComponent("clips_index.json")
    }

    func loadAll() -> [SavedClip] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return try dec.decode([SavedClip].self, from: data)
        } catch {
            log.error("Load failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func save(_ clips: [SavedClip]) {
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = .prettyPrinted
            try enc.encode(clips).write(to: indexURL)
        } catch {
            log.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func append(_ clip: SavedClip) {
        var all = loadAll()
        all.insert(clip, at: 0)
        save(all)
    }

    func delete(_ clipID: UUID) {
        var all = loadAll()
        guard let idx = all.firstIndex(where: { $0.id == clipID }) else { return }
        let clip = all[idx]
        try? FileManager.default.removeItem(at: clip.clipURL)
        if let t = clip.thumbnailURL { try? FileManager.default.removeItem(at: t) }
        all.remove(at: idx)
        save(all)
    }

    // MARK: - Save release-to-end clip

    func saveReleaseClip(from videoURL: URL, delivery: Delivery) async throws -> SavedClip {
        guard let releaseFrame = delivery.releaseFrame,
              let arrivalFrame = delivery.arrivalFrame else {
            throw ClipSaveError.noReleaseFrame
        }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)

        let releaseTime = Double(releaseFrame) / delivery.fps
        let arrivalTime = Double(arrivalFrame) / delivery.fps
        let startTime = max(0, releaseTime - 0.5)
        let endTime = min(totalDuration, arrivalTime + 0.5)

        let releaseInClip = releaseTime - startTime
        let arrivalInClip = arrivalTime - startTime

        return try await exportClip(
            asset: asset,
            startSeconds: startTime,
            endSeconds: endTime,
            delivery: delivery,
            kind: .releaseToEnd,
            releaseTimeInClip: releaseInClip,
            arrivalTimeInClip: arrivalInClip
        )
    }

    // MARK: - Save full video

    func saveFullVideo(from videoURL: URL, delivery: Delivery) async throws -> SavedClip {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)

        let releaseInClip = delivery.releaseFrame.map { Double($0) / delivery.fps }
        let arrivalInClip = delivery.arrivalFrame.map { Double($0) / delivery.fps }

        return try await exportClip(
            asset: asset,
            startSeconds: 0,
            endSeconds: CMTimeGetSeconds(duration),
            delivery: delivery,
            kind: .full,
            releaseTimeInClip: releaseInClip,
            arrivalTimeInClip: arrivalInClip
        )
    }

    // MARK: - Private

    private func exportClip(
        asset: AVURLAsset,
        startSeconds: Double,
        endSeconds: Double,
        delivery: Delivery,
        kind: SavedClip.ClipKind,
        releaseTimeInClip: Double? = nil,
        arrivalTimeInClip: Double? = nil
    ) async throws -> SavedClip {
        let clipID = UUID()
        let fileName = "\(kind.rawValue)_\(clipID.uuidString).mp4"
        let destURL = Self.clipsDir.appendingPathComponent(fileName)

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            end: CMTime(seconds: endSeconds, preferredTimescale: 600)
        )

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ClipSaveError.exportFailed
        }
        session.outputURL = destURL
        session.outputFileType = .mp4
        session.timeRange = timeRange
        await session.export()

        guard session.status == .completed else {
            throw session.error ?? ClipSaveError.exportFailed
        }

        let thumbName = try? await makeThumbnail(for: destURL, id: clipID)

        // Save to Photos
        await saveToPhotos(destURL)

        let clip = SavedClip(
            id: clipID,
            createdAt: Date(),
            clipFileName: fileName,
            thumbnailFileName: thumbName,
            durationSeconds: endSeconds - startSeconds,
            kind: kind,
            speedKMH: delivery.speedKMH,
            releaseFrame: delivery.releaseFrame,
            arrivalFrame: delivery.arrivalFrame,
            releaseTimeInClip: releaseTimeInClip,
            arrivalTimeInClip: arrivalTimeInClip
        )
        append(clip)
        log.debug("Saved \(kind.rawValue) clip: \(fileName)")
        return clip
    }

    private func makeThumbnail(for url: URL, id: UUID) async throws -> String {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 400)
        let (cg, _) = try await gen.image(at: CMTime(seconds: 0.3, preferredTimescale: 600))
        let name = "\(id.uuidString).jpg"
        if let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) {
            try data.write(to: Self.thumbsDir.appendingPathComponent(name))
        }
        return name
    }

    private func saveToPhotos(_ url: URL) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        var ok = status == .authorized || status == .limited
        if !ok {
            let req = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            ok = req == .authorized || req == .limited
        }
        guard ok else { return }
        do {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                } completionHandler: { success, err in
                    if success { c.resume() }
                    else { c.resume(throwing: err ?? ClipSaveError.exportFailed) }
                }
            }
        } catch {
            log.error("Photos save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

enum ClipSaveError: LocalizedError {
    case noReleaseFrame
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noReleaseFrame: return "No release frame marked"
        case .exportFailed: return "Export failed"
        }
    }
}

// MARK: - Frame Marker Store

struct FrameMarkers: Codable {
    let releaseFrame: Int
    let arrivalFrame: Int
    let distanceMeters: Double
}

final class FrameMarkerStore {
    static let shared = FrameMarkerStore()

    private var storeURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("frame_markers.json")
    }

    private func loadMap() -> [String: FrameMarkers] {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let map = try? JSONDecoder().decode([String: FrameMarkers].self, from: data) else { return [:] }
        return map
    }

    private func saveMap(_ map: [String: FrameMarkers]) {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        try? enc.encode(map).write(to: storeURL)
    }

    func save(videoURL: URL, releaseFrame: Int, arrivalFrame: Int, distanceMeters: Double) {
        var map = loadMap()
        map[videoURL.lastPathComponent] = FrameMarkers(
            releaseFrame: releaseFrame, arrivalFrame: arrivalFrame, distanceMeters: distanceMeters
        )
        saveMap(map)
    }

    func lookup(videoURL: URL) -> FrameMarkers? {
        loadMap()[videoURL.lastPathComponent]
    }
}
