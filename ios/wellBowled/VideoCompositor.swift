import AVFoundation
import CoreGraphics
import CoreText
import UIKit

/// Burns skeleton overlay + analysis labels into an exportable 9:16 MP4.
/// Uses AVAssetReader/Writer pipeline — reads each frame as CVPixelBuffer,
/// draws skeleton via CoreGraphics, writes composited frame back.
final class VideoCompositor {

    struct Input {
        let clipURL: URL
        let poseFrames: [FramePoseLandmarks]
        let expertAnalysis: ExpertAnalysis?
        let phases: [AnalysisPhase]
        let speedKph: Double?
        let dnaMatch: BowlingDNAMatch?
    }

    enum CompositorError: Error, LocalizedError {
        case cannotCreateReader
        case cannotCreateWriter
        case noVideoTrack
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .cannotCreateReader: return "Cannot create asset reader"
            case .cannotCreateWriter: return "Cannot create asset writer"
            case .noVideoTrack: return "No video track in source"
            case .exportFailed(let msg): return "Export failed: \(msg)"
            }
        }
    }

    // MARK: - Drawing constants

    private static let boneLineWidth: CGFloat = 3.0
    private static let jointRadius: CGFloat = 5.0
    private static let visibilityThreshold: Float = 0.5
    private static let labelFontSize: CGFloat = 24.0
    private static let badgeFontSize: CGFloat = 18.0
    private static let legendFontSize: CGFloat = 14.0

    // Brand colors as CGColor
    private static let goodCG = UIColor(red: 0.125, green: 0.788, blue: 0.592, alpha: 1.0).cgColor
    private static let attentionCG = UIColor(red: 0.957, green: 0.635, blue: 0.380, alpha: 1.0).cgColor
    private static let injuryRiskCG = UIColor(red: 0.902, green: 0.224, blue: 0.275, alpha: 1.0).cgColor
    private static let whiteCG = UIColor.white.cgColor
    private static let bgPillCG = UIColor(white: 0, alpha: 0.6).cgColor
    private static let peacockBlueCG = UIColor(red: 0, green: 0.427, blue: 0.467, alpha: 0.85).cgColor

    // MARK: - Public API

    /// Composites skeleton overlay onto video and returns output MP4 URL.
    func composite(_ input: Input) async throws -> URL {
        let asset = AVURLAsset(url: input.clipURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw CompositorError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)
        let videoSize = CGSize(width: abs(transformedSize.width), height: abs(transformedSize.height))
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)

        // Output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("composited_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        // Reader
        let reader = try AVAssetReader(asset: asset)

        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerSettings)
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else { throw CompositorError.cannotCreateReader }
        reader.add(readerOutput)

        // Writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let writerSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
        writerInput.expectsMediaDataInRealTime = false
        writerInput.transform = preferredTransform

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(videoSize.width),
                kCVPixelBufferHeightKey as String: Int(videoSize.height)
            ]
        )

        guard writer.canAdd(writerInput) else { throw CompositorError.cannotCreateWriter }
        writer.add(writerInput)

        // Audio passthrough
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        var audioReaderOutput: AVAssetReaderTrackOutput?
        var audioWriterInput: AVAssetWriterInput?

        if let audioTrack = audioTracks.first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            if reader.canAdd(audioOutput) {
                reader.add(audioOutput)
                audioReaderOutput = audioOutput
            }

            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            audioInput.expectsMediaDataInRealTime = false
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                audioWriterInput = audioInput
            }
        }

        // Start
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process video frames
        let sortedFrames = input.poseFrames.sorted { $0.timestamp < $1.timestamp }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.wellbowled.compositor.video")) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        continuation.resume()
                        return
                    }

                    let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let timestamp = presentationTime.seconds

                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        continue
                    }

                    // Draw overlay onto pixel buffer
                    self.drawOverlay(
                        on: pixelBuffer,
                        videoSize: videoSize,
                        timestamp: timestamp,
                        sortedFrames: sortedFrames,
                        expertAnalysis: input.expertAnalysis,
                        phases: input.phases,
                        speedKph: input.speedKph,
                        dnaMatch: input.dnaMatch
                    )

                    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
                }
            }
        }

        // Process audio
        if let audioOutput = audioReaderOutput, let audioInput = audioWriterInput {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "com.wellbowled.compositor.audio")) {
                    while audioInput.isReadyForMoreMediaData {
                        guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
                            audioInput.markAsFinished()
                            continuation.resume()
                            return
                        }
                        audioInput.append(sampleBuffer)
                    }
                }
            }
        }

        await writer.finishWriting()

        guard writer.status == .completed else {
            throw CompositorError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
        }

        return outputURL
    }

    // MARK: - Frame Matching

    /// Binary search for closest pose frame by timestamp.
    static func findClosestFrame(for timestamp: Double, in frames: [FramePoseLandmarks]) -> FramePoseLandmarks? {
        guard !frames.isEmpty else { return nil }

        var left = 0
        var right = frames.count - 1
        var closestIndex = 0
        var minDiff = abs(frames[0].timestamp - timestamp)

        while left <= right {
            let mid = (left + right) / 2
            let diff = abs(frames[mid].timestamp - timestamp)

            if diff < minDiff {
                minDiff = diff
                closestIndex = mid
            }

            if frames[mid].timestamp < timestamp {
                left = mid + 1
            } else {
                right = mid - 1
            }
        }
        return frames[closestIndex]
    }

    // MARK: - Color Conversion

    /// Maps ExpertAnalysisMapper color logic to CGColor for CoreGraphics drawing.
    static func cgColor(for landmarkName: String, timestamp: Double, expertAnalysis: ExpertAnalysis?) -> CGColor {
        let colorString = ExpertAnalysisMapper.getJointColor(
            jointName: landmarkName,
            expertAnalysis: expertAnalysis,
            timestamp: timestamp
        )
        switch colorString {
        case "red": return injuryRiskCG
        case "yellow": return attentionCG
        case "green": return goodCG
        default: return whiteCG
        }
    }

    /// Returns current phase for a given timestamp.
    static func currentPhase(at timestamp: Double, phases: [AnalysisPhase]) -> AnalysisPhase? {
        phases.first { phase in
            guard let clipTimestamp = phase.clipTimestamp else { return false }
            // Each phase covers from its clipTimestamp to the next phase's clipTimestamp
            let sortedPhases = phases
                .filter { $0.clipTimestamp != nil }
                .sorted { ($0.clipTimestamp ?? 0) < ($1.clipTimestamp ?? 0) }

            guard let idx = sortedPhases.firstIndex(where: { $0.id == phase.id }) else { return false }
            let start = clipTimestamp
            let end: Double
            if idx + 1 < sortedPhases.count {
                end = sortedPhases[idx + 1].clipTimestamp ?? .greatestFiniteMagnitude
            } else {
                end = .greatestFiniteMagnitude
            }
            return timestamp >= start && timestamp < end
        }
    }

    // MARK: - Drawing

    private func drawOverlay(
        on pixelBuffer: CVPixelBuffer,
        videoSize: CGSize,
        timestamp: Double,
        sortedFrames: [FramePoseLandmarks],
        expertAnalysis: ExpertAnalysis?,
        phases: [AnalysisPhase],
        speedKph: Double?,
        dnaMatch: BowlingDNAMatch?
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return }

        let size = CGSize(width: width, height: height)

        // CoreGraphics has origin at bottom-left; flip to top-left
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        // 1. Draw skeleton
        if let frame = Self.findClosestFrame(for: timestamp, in: sortedFrames) {
            drawSkeleton(context: context, frame: frame, videoSize: size, timestamp: timestamp, expertAnalysis: expertAnalysis)
        }

        // 2. Draw phase label
        if let phase = Self.currentPhase(at: timestamp, phases: phases) {
            drawPhaseLabel(context: context, phase: phase, videoSize: size)
        }

        // 3. Draw speed badge
        if let kph = speedKph {
            drawSpeedBadge(context: context, kph: kph, videoSize: size)
        }

        // 4. Draw DNA match card
        if let dna = dnaMatch {
            drawDNACard(context: context, match: dna, videoSize: size)
        }

        // 5. Draw color legend
        drawColorLegend(context: context, videoSize: size)
    }

    private func drawSkeleton(
        context: CGContext,
        frame: FramePoseLandmarks,
        videoSize: CGSize,
        timestamp: Double,
        expertAnalysis: ExpertAnalysis?
    ) {
        let landmarks = frame.landmarks

        // Draw bones
        context.setLineWidth(Self.boneLineWidth)
        context.setLineCap(.round)

        for connection in SkeletonRenderer.connections {
            let fromIdx = connection[0]
            let toIdx = connection[1]

            guard let from = landmarks.first(where: { $0.index == fromIdx }),
                  let to = landmarks.first(where: { $0.index == toIdx }),
                  from.visibility >= Self.visibilityThreshold,
                  to.visibility >= Self.visibilityThreshold else { continue }

            let fromPt = SkeletonRenderer.toScreenCoordinates(from, size: videoSize)
            let toPt = SkeletonRenderer.toScreenCoordinates(to, size: videoSize)

            // Use color of the "from" landmark
            let color = Self.cgColor(for: from.name, timestamp: timestamp, expertAnalysis: expertAnalysis)
            context.setStrokeColor(color)
            context.setAlpha(0.85)

            context.move(to: fromPt)
            context.addLine(to: toPt)
            context.strokePath()
        }

        // Draw key joints
        for landmark in landmarks {
            guard SkeletonRenderer.keyJointIndices.contains(landmark.index),
                  landmark.visibility >= Self.visibilityThreshold else { continue }

            let pt = SkeletonRenderer.toScreenCoordinates(landmark, size: videoSize)
            let color = Self.cgColor(for: landmark.name, timestamp: timestamp, expertAnalysis: expertAnalysis)

            // Filled circle
            context.setFillColor(color)
            context.setAlpha(1.0)
            let rect = CGRect(
                x: pt.x - Self.jointRadius,
                y: pt.y - Self.jointRadius,
                width: Self.jointRadius * 2,
                height: Self.jointRadius * 2
            )
            context.fillEllipse(in: rect)

            // White border
            context.setStrokeColor(Self.whiteCG)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: rect)
        }
    }

    private func drawPhaseLabel(context: CGContext, phase: AnalysisPhase, videoSize: CGSize) {
        let text = phase.name
        let statusColor: CGColor = phase.isGood ? Self.goodCG : Self.attentionCG

        let font = CTFontCreateWithName("SF Pro Display" as CFString, Self.labelFontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let padding: CGFloat = 12
        let pillWidth = bounds.width + padding * 2
        let pillHeight = bounds.height + padding
        let x = (videoSize.width - pillWidth) / 2
        let y: CGFloat = 60  // top area

        // Background pill
        let pillRect = CGRect(x: x, y: y, width: pillWidth, height: pillHeight)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil)
        context.setFillColor(Self.bgPillCG)
        context.addPath(pillPath)
        context.fillPath()

        // Status dot
        let dotSize: CGFloat = 8
        let dotRect = CGRect(x: x + padding - 2, y: y + (pillHeight - dotSize) / 2, width: dotSize, height: dotSize)
        context.setFillColor(statusColor)
        context.fillEllipse(in: dotRect)

        // Text
        context.setFillColor(Self.whiteCG)
        context.textPosition = CGPoint(x: x + padding + dotSize + 6, y: y + pillHeight - padding + 2)
        CTLineDraw(line, context)
    }

    private func drawSpeedBadge(context: CGContext, kph: Double, videoSize: CGSize) {
        let text = String(format: "%.0f kph", kph)
        let font = CTFontCreateWithName("SF Pro Display" as CFString, Self.badgeFontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let padding: CGFloat = 10
        let x: CGFloat = 16
        let y: CGFloat = 120
        let pillWidth = bounds.width + padding * 2
        let pillHeight = bounds.height + padding

        let pillRect = CGRect(x: x, y: y, width: pillWidth, height: pillHeight)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil)
        context.setFillColor(Self.peacockBlueCG)
        context.addPath(pillPath)
        context.fillPath()

        context.textPosition = CGPoint(x: x + padding, y: y + pillHeight - padding + 2)
        CTLineDraw(line, context)
    }

    private func drawDNACard(context: CGContext, match: BowlingDNAMatch, videoSize: CGSize) {
        let text = "\(match.bowlerName) \(String(format: "%.0f", match.similarityPercent))%"
        let font = CTFontCreateWithName("SF Pro Display" as CFString, Self.badgeFontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

        let padding: CGFloat = 10
        let pillWidth = bounds.width + padding * 2
        let pillHeight = bounds.height + padding
        let x = videoSize.width - pillWidth - 16
        let y: CGFloat = 120

        let pillRect = CGRect(x: x, y: y, width: pillWidth, height: pillHeight)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillHeight / 2, cornerHeight: pillHeight / 2, transform: nil)
        context.setFillColor(Self.bgPillCG)
        context.addPath(pillPath)
        context.fillPath()

        // DNA icon placeholder (small circle)
        let iconSize: CGFloat = 10
        let iconRect = CGRect(x: x + padding - 2, y: y + (pillHeight - iconSize) / 2, width: iconSize, height: iconSize)
        context.setFillColor(Self.goodCG)
        context.fillEllipse(in: iconRect)

        context.textPosition = CGPoint(x: x + padding + iconSize + 4, y: y + pillHeight - padding + 2)
        CTLineDraw(line, context)
    }

    private func drawColorLegend(context: CGContext, videoSize: CGSize) {
        let items: [(String, CGColor)] = [
            ("Good", Self.goodCG),
            ("Attention", Self.attentionCG),
            ("Injury Risk", Self.injuryRiskCG)
        ]

        let font = CTFontCreateWithName("SF Pro Display" as CFString, Self.legendFontSize, nil)
        let padding: CGFloat = 8
        let dotSize: CGFloat = 8
        let itemSpacing: CGFloat = 16
        let y = videoSize.height - 40

        // Calculate total width
        var totalWidth: CGFloat = 0
        var itemWidths: [CGFloat] = []
        for (label, _) in items {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let attrStr = NSAttributedString(string: label, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            let w = dotSize + 4 + bounds.width
            itemWidths.append(w)
            totalWidth += w
        }
        totalWidth += itemSpacing * CGFloat(items.count - 1)

        // Background pill
        let bgPadding: CGFloat = 10
        let bgRect = CGRect(
            x: (videoSize.width - totalWidth) / 2 - bgPadding,
            y: y - 4,
            width: totalWidth + bgPadding * 2,
            height: 24
        )
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.setFillColor(Self.bgPillCG)
        context.addPath(bgPath)
        context.fillPath()

        // Draw items
        var xOffset = (videoSize.width - totalWidth) / 2
        for (i, (label, color)) in items.enumerated() {
            // Dot
            context.setFillColor(color)
            context.fillEllipse(in: CGRect(x: xOffset, y: y + 4, width: dotSize, height: dotSize))

            // Label
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let attrStr = NSAttributedString(string: label, attributes: attrs)
            let line = CTLineCreateWithAttributedString(attrStr)

            context.textPosition = CGPoint(x: xOffset + dotSize + 4, y: y)
            CTLineDraw(line, context)

            xOffset += itemWidths[i] + itemSpacing
        }
    }
}
