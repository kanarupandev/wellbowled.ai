import Foundation
import AVFoundation
import Combine
import QuartzCore
import os

private let skeletonLog = Logger(subsystem: "com.wellbowled", category: "SkeletonSync")

// MARK: - Skeleton Sync Controller

@MainActor
class SkeletonSyncController: ObservableObject {

    // MARK: - Published Properties

    @Published var currentFrame: FramePoseLandmarks?
    @Published var currentColorMap: [String: Color] = [:]

    // MARK: - Private Properties

    private let player: AVPlayer
    private let allFrames: [FramePoseLandmarks]
    private let expertAnalysis: ExpertAnalysis?
    private let mapper: ExpertAnalysisMapper?

    /// Video natural size for aspect-fit mapping. Updated asynchronously.
    @Published var videoNaturalSize: CGSize = .zero

    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0
    private var frameUpdateCount = 0

    // MARK: - Initialization

    init(player: AVPlayer, frames: [FramePoseLandmarks], expertAnalysis: ExpertAnalysis? = nil) {
        self.player = player
        self.allFrames = frames
        self.expertAnalysis = expertAnalysis
        self.mapper = nil  // ExpertAnalysisMapper is now static

        skeletonLog.info("SkeletonSyncController created: frames=\(frames.count), hasExpertAnalysis=\(expertAnalysis != nil)")
        print("🦴 [SkeletonSync] Created: frames=\(frames.count), hasExpertAnalysis=\(expertAnalysis != nil)")
        if let first = frames.first, let last = frames.last {
            skeletonLog.debug("Frame range: \(first.timestamp)s → \(last.timestamp)s, landmarks/frame=\(first.landmarks.count)")
        }
        if let ea = expertAnalysis {
            skeletonLog.debug("ExpertAnalysis phases=\(ea.phases.count)")
            for phase in ea.phases {
                let goodCount = phase.feedback.good.count
                let slowCount = phase.feedback.slow.count
                let riskCount = phase.feedback.injuryRisk.count
                skeletonLog.debug("  Phase '\(phase.phaseName, privacy: .public)': good=\(goodCount) slow=\(slowCount) risk=\(riskCount)")
            }
        }

        setupDisplayLink()
        loadVideoNaturalSize()
    }

    private func loadVideoNaturalSize() {
        guard let asset = (player.currentItem?.asset) else { return }
        Task { @MainActor in
            if let tracks = try? await asset.loadTracks(withMediaType: .video),
               let track = tracks.first,
               let size = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let transformed = size.applying(transform)
                self.videoNaturalSize = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                print("🦴 [SkeletonSync] Video natural size: \(self.videoNaturalSize)")
            }
        }
    }

    // MARK: - Lifecycle

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Public Methods

    func startSync() {
        displayLink?.isPaused = false
        skeletonLog.debug("SkeletonSync started (displayLink unpaused)")
    }

    func stopSync() {
        displayLink?.isPaused = true
        skeletonLog.debug("SkeletonSync stopped (displayLink paused), totalFrameUpdates=\(self.frameUpdateCount)")
    }

    func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
        skeletonLog.debug("SkeletonSync cleaned up, totalFrameUpdates=\(self.frameUpdateCount)")
    }

    // MARK: - Private Methods

    private func setupDisplayLink() {
        // Create CADisplayLink for 60Hz updates
        displayLink = CADisplayLink(target: self, selector: #selector(updateFrame))
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.preferredFramesPerSecond = 60 // Target 60 FPS
    }

    @objc private func updateFrame(displayLink: CADisplayLink) {
        // Get current video playback time
        let currentTime = player.currentTime().seconds

        // Throttle updates to avoid excessive re-rendering
        let timeSinceLastUpdate = displayLink.timestamp - lastUpdateTime
        if timeSinceLastUpdate < 0.016 { // ~60 FPS (1/60 ≈ 0.016s)
            return
        }
        lastUpdateTime = displayLink.timestamp

        // Find closest frame by timestamp
        guard let closestFrame = findClosestFrame(for: currentTime) else {
            return
        }

        // Only update if frame changed
        if currentFrame?.frameNumber != closestFrame.frameNumber {
            currentFrame = closestFrame
            frameUpdateCount += 1

            if frameUpdateCount == 1 {
                skeletonLog.info("First skeleton frame rendered: frame#\(closestFrame.frameNumber) t=\(currentTime)s landmarks=\(closestFrame.landmarks.count)")
                print("🦴 [SkeletonSync] First frame rendered: frame#\(closestFrame.frameNumber) t=\(currentTime)s")
            } else if frameUpdateCount % 120 == 0 {
                skeletonLog.debug("Skeleton frame update #\(self.frameUpdateCount): frame#\(closestFrame.frameNumber) t=\(currentTime)s")
            }

            // Update color map based on Expert analysis
            updateColorMap(for: closestFrame, at: currentTime)
        }
    }

    private func findClosestFrame(for timestamp: Double) -> FramePoseLandmarks? {
        // Binary search for closest frame (O(log n))
        guard !allFrames.isEmpty else { return nil }

        var left = 0
        var right = allFrames.count - 1
        var closestFrame = allFrames[0]
        var minDiff = abs(allFrames[0].timestamp - timestamp)

        while left <= right {
            let mid = (left + right) / 2
            let frame = allFrames[mid]
            let diff = abs(frame.timestamp - timestamp)

            if diff < minDiff {
                minDiff = diff
                closestFrame = frame
            }

            if frame.timestamp < timestamp {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }

        return closestFrame
    }

    private func updateColorMap(for frame: FramePoseLandmarks, at timestamp: Double) {
        var newColorMap: [String: Color] = [:]

        for landmark in frame.landmarks {
            let color = ExpertAnalysisMapper.getColor(for: landmark.name, timestamp: timestamp, expertAnalysis: expertAnalysis)
            newColorMap[landmark.name] = color
        }

        currentColorMap = newColorMap
    }
}

// MARK: - Skeleton Overlay View with Sync

import SwiftUI

struct SyncedSkeletonOverlayView: View {
    @ObservedObject var syncController: SkeletonSyncController
    let config: SkeletonRenderer.RenderConfig

    init(syncController: SkeletonSyncController, config: SkeletonRenderer.RenderConfig = SkeletonRenderer.RenderConfig()) {
        self.syncController = syncController
        self.config = config
    }

    var body: some View {
        GeometryReader { geometry in
            if let frame = syncController.currentFrame {
                Canvas { context, size in
                    // Draw connections first (behind joints)
                    drawConnections(context: context, size: size, frame: frame)

                    // Draw joints on top
                    drawJoints(context: context, size: size, frame: frame)
                }
                .drawingGroup() // Enable Metal GPU acceleration
            }
        }
        .onAppear {
            skeletonLog.info("SyncedSkeletonOverlayView appeared — starting sync")
            print("🦴 [SkeletonSync] Overlay view APPEARED")
            syncController.startSync()
        }
        .onDisappear {
            skeletonLog.info("SyncedSkeletonOverlayView disappeared — stopping sync")
            print("🦴 [SkeletonSync] Overlay view DISAPPEARED")
            syncController.stopSync()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing Methods

    private var videoAspectRatio: CGFloat {
        let ns = syncController.videoNaturalSize
        guard ns.width > 0, ns.height > 0 else { return 0 }
        return ns.width / ns.height
    }

    private func toScreen(_ landmark: PoseLandmark, size: CGSize) -> CGPoint {
        let ar = videoAspectRatio
        if ar > 0 {
            return SkeletonRenderer.toScreenCoordinates(landmark, containerSize: size, videoAspectRatio: ar)
        }
        return SkeletonRenderer.toScreenCoordinates(landmark, size: size)
    }

    private func drawConnections(context: GraphicsContext, size: CGSize, frame: FramePoseLandmarks) {
        let visibleLandmarks = SkeletonRenderer.filterVisible(
            frame.landmarks,
            threshold: config.visibilityThreshold
        )

        for connection in SkeletonRenderer.connections {
            guard connection.count == 2,
                  let startLandmark = visibleLandmarks.first(where: { $0.index == connection[0] }),
                  let endLandmark = visibleLandmarks.first(where: { $0.index == connection[1] }) else {
                continue
            }

            let p1 = toScreen(startLandmark, size: size)
            let p2 = toScreen(endLandmark, size: size)

            // Color the connection based on the joint colors
            let startColor = syncController.currentColorMap[startLandmark.name] ?? .white
            let endColor = syncController.currentColorMap[endLandmark.name] ?? .white
            let lineColor = (startColor == endColor) ? startColor : .white

            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)

            context.stroke(
                path,
                with: .color(lineColor.opacity(config.lineOpacity)),
                lineWidth: config.lineWidth
            )
        }
    }

    private func drawJoints(context: GraphicsContext, size: CGSize, frame: FramePoseLandmarks) {
        let keyJoints = SkeletonRenderer.filterKeyJoints(
            frame.landmarks,
            threshold: config.visibilityThreshold
        )

        for landmark in keyJoints {
            let point = toScreen(landmark, size: size)
            let color = syncController.currentColorMap[landmark.name] ?? .white

            let circle = Path(ellipseIn: CGRect(
                x: point.x - config.jointRadius,
                y: point.y - config.jointRadius,
                width: config.jointRadius * 2,
                height: config.jointRadius * 2
            ))

            context.fill(circle, with: .color(color))
        }
    }
}
