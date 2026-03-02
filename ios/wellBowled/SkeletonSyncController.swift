import Foundation
import AVFoundation
import Combine
import QuartzCore

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

    private var displayLink: CADisplayLink?
    private var lastUpdateTime: CFTimeInterval = 0

    // MARK: - Initialization

    init(player: AVPlayer, frames: [FramePoseLandmarks], expertAnalysis: ExpertAnalysis? = nil) {
        self.player = player
        self.allFrames = frames
        self.expertAnalysis = expertAnalysis
        self.mapper = nil  // ExpertAnalysisMapper is now static

        setupDisplayLink()
    }

    // MARK: - Lifecycle

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Public Methods

    func startSync() {
        displayLink?.isPaused = false
    }

    func stopSync() {
        displayLink?.isPaused = true
    }

    func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
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
            syncController.startSync()
        }
        .onDisappear {
            syncController.stopSync()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing Methods

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

            let p1 = SkeletonRenderer.toScreenCoordinates(startLandmark, size: size)
            let p2 = SkeletonRenderer.toScreenCoordinates(endLandmark, size: size)

            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)

            context.stroke(
                path,
                with: .color(.white.opacity(config.lineOpacity)),
                lineWidth: config.lineWidth
            )
        }
    }

    private func drawJoints(context: GraphicsContext, size: CGSize, frame: FramePoseLandmarks) {
        let visibleLandmarks = SkeletonRenderer.filterVisible(
            frame.landmarks,
            threshold: config.visibilityThreshold
        )

        for landmark in visibleLandmarks {
            let point = SkeletonRenderer.toScreenCoordinates(landmark, size: size)
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
