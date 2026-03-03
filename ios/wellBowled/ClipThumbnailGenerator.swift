import AVFoundation
import UIKit

enum ClipThumbnailGenerator {
    /// Uses the release offset inside the 5s clip (default 3.0s) to create a thumbnail.
    static func releaseThumbnail(from clipURL: URL, releaseOffset: Double = WBConfig.clipPreRoll) -> UIImage? {
        let asset = AVURLAsset(url: clipURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 1280)

        let durationSeconds = asset.duration.seconds
        let safeOffset: Double
        if durationSeconds.isFinite, durationSeconds > 0 {
            safeOffset = min(max(releaseOffset, 0.0), max(durationSeconds - 0.05, 0.0))
        } else {
            safeOffset = max(releaseOffset, 0.0)
        }

        let time = CMTime(seconds: safeOffset, preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

