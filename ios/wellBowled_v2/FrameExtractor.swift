import AVFoundation
import UIKit

@MainActor
class FrameExtractor: ObservableObject {
    private var generator: AVAssetImageGenerator?

    let videoURL: URL
    let fps: Double
    let totalFrames: Int
    let duration: Double

    @Published var currentFrame: UIImage?
    @Published var currentFrameIndex: Int = 0

    init(url: URL, fps: Double, duration: Double, totalFrames: Int) {
        self.videoURL = url
        self.fps = fps
        self.duration = duration
        self.totalFrames = max(1, totalFrames)

        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero // exact frame
        gen.requestedTimeToleranceAfter = .zero  // exact frame
        gen.maximumSize = CGSize(width: 1920, height: 1080)
        self.generator = gen
    }

    func loadFirstFrame() { seekToFrame(0) }

    func seekToFrame(_ index: Int) {
        let clamped = max(0, min(index, totalFrames - 1))
        currentFrameIndex = clamped
        let time = CMTime(value: CMTimeValue(clamped), timescale: CMTimeScale(fps))
        if let cg = try? generator?.copyCGImage(at: time, actualTime: nil) {
            currentFrame = UIImage(cgImage: cg)
        }
    }

    func nextFrame() { seekToFrame(currentFrameIndex + 1) }
    func previousFrame() { seekToFrame(currentFrameIndex - 1) }
    func advance(by n: Int) { seekToFrame(currentFrameIndex + n) }

    var currentTimeSeconds: Double { Double(currentFrameIndex) / fps }
    var currentTimeString: String { String(format: "%.3fs", currentTimeSeconds) }
}
