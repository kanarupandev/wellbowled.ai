import AVFoundation
import Foundation
import os

private let log = Logger(subsystem: "com.wellbowled", category: "ClipExtractor")

/// Extracts short clips from a recording around a delivery timestamp.
final class ClipExtractor: ClipExtracting {

    func extractClip(
        from recordingURL: URL,
        at timestamp: Double,
        preRoll: Double,
        postRoll: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: recordingURL)
        let duration = try await asset.load(.duration)

        // AVCaptureMovieFileOutput may preserve session-clock CMTimes (start > 0).
        // Detect actual asset start so clip seek positions land correctly.
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let trackTimeRange = try await tracks.first?.load(.timeRange)
        let assetStart = CMTimeGetSeconds(trackTimeRange?.start ?? .zero)
        let assetEnd = assetStart + CMTimeGetSeconds(duration)

        // Shift the 0-based clip timestamp into the asset's time domain.
        let seekTime = timestamp + assetStart
        let startTime = max(assetStart, seekTime - preRoll)
        let endTime = min(assetEnd, seekTime + postRoll)

        log.debug("Clip seek: timestamp=\(timestamp), assetStart=\(assetStart), seekTime=\(seekTime), range=\(startTime)-\(endTime)")

        let timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 600),
            end: CMTime(seconds: endTime, preferredTimescale: 600)
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw ClipError.exportSessionCreationFailed
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = timeRange

        log.debug("Extracting clip: \(startTime)s-\(endTime)s from \(recordingURL.lastPathComponent)")
        await exportSession.export()

        guard exportSession.status == .completed else {
            log.error("Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            throw exportSession.error ?? ClipError.exportFailed
        }

        log.debug("Clip extracted: \(outputURL.lastPathComponent)")
        return outputURL
    }
}

enum ClipError: LocalizedError {
    case exportSessionCreationFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .exportSessionCreationFailed: return "Cannot create export session"
        case .exportFailed: return "Clip export failed"
        }
    }
}
