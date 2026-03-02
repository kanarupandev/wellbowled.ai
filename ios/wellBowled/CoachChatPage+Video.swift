import SwiftUI
import AVKit

// MARK: - CoachChatPage Video Views & Setup
extension CoachChatPage {

    // MARK: - Full Screen Video (State 1 & 2)

    var fullScreenVideoArea: some View {
        ZStack {
            // Layer 1: Dark background (visible when X-Ray is at 100%)
            Color.black

            // Layer 2: Video (fades out as X-Ray increases)
            if let p = player {
                VideoPlayer(player: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .ignoresSafeArea()
                    .opacity(1.0 - fadeLevel)
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }

            // Layer 3: Skeleton overlay (fades in as fadeLevel increases, drawn on top of video)
            // Shows as soon as pose data is ready — independent of overlay video state
            if let syncController = skeletonSyncController {
                SyncedSkeletonOverlayView(syncController: syncController)
                    .opacity(fadeLevel)  // ← 0 = hidden, 1 = fully visible over video
                    .allowsHitTesting(false)
            }

            // Pause overlay
            if player != nil && !isVideoPlaying {
                Color.black.opacity(0.3)
                Image(systemName: "play.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.9))
            }

            // Annotating spinner
            if shouldShowLoadingSpinner {
                ZStack {
                    Color.black.opacity(0.7)
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.5)
                        Text("Annotating video...")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .allowsHitTesting(false)
            }

            // X-Ray controls at bottom
            VStack {
                Spacer()

                HStack {
                    Spacer()
                    // X-Ray Vision Slider - 80% width centered
                    XRayVisionSlider(fadeLevel: $fadeLevel)
                        .frame(maxWidth: 400)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Color legend
                OverlayColorLegend()
                    .padding(.bottom, 100)
                    .allowsHitTesting(false)
            }
        }
        .onTapGesture {
            if player != nil {
                isVideoPlaying.toggle()
                if isVideoPlaying { player?.play() } else { player?.pause() }
                print("🎬 [CoachPage] Video tap - playing: \(isVideoPlaying)")
            }
        }
    }

    // MARK: - Buttons

    var expandButton: some View {
        Button(action: {
            print("💬 [CoachPage] Expand button tapped")
            withAnimation(.easeInOut(duration: 0.3)) {
                isChatExpanded = true
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .bold))
                Text("Chat")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignSystem.Colors.primary)
            .cornerRadius(12)
        }
    }

    var collapseButton: some View {
        Button(action: {
            print("💬 [CoachPage] Collapse button tapped")
            withAnimation(.easeInOut(duration: 0.3)) {
                isChatExpanded = false
            }
        }) {
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.primary)
                .cornerRadius(12)
        }
    }

    // MARK: - Video Setup & State Transitions

    func setupInitialVideo() async {
        print("🎬 [CoachPage] setupInitialVideo() called")

        // Priority 1: Use cached annotated if available
        if let annotatedURL = overlayURL {
            print("🎬 [CoachPage] ✅ Cached annotated video found")
            print("   URL: \(annotatedURL.lastPathComponent)")
            videoState = .playingAnnotated(annotatedURL)
            await MainActor.run {
                setupVideoPlayer(url: annotatedURL)
            }
            return
        }

        // Priority 2: Use original and wait for overlay
        if let originalURL = originalVideoURL {
            print("🎬 [CoachPage] Starting with original video")
            print("   URL: \(originalURL.lastPathComponent)")
            videoState = .playingOriginal(originalURL)
            await MainActor.run {
                setupVideoPlayer(url: originalURL)
            }
            return
        }

        print("⚠️ [CoachPage] No video URL available!")
    }

    func handleOverlayReady(oldURL: URL?, newURL: URL?) {
        print("🎬 [CoachPage] ========== OVERLAY READY ==========")
        print("   Old URL: \(oldURL?.lastPathComponent ?? "nil")")
        print("   New URL: \(newURL?.lastPathComponent ?? "nil")")

        guard let newURL = newURL, oldURL == nil else {
            print("   ⚠️ Not a nil→URL transition, ignoring")
            return
        }
        guard case .playingOriginal = videoState else {
            print("   ⚠️ Not playing original, ignoring")
            return
        }

        print("   ✅ Conditions met, swapping to annotated video")

        videoState = .loading
        player?.pause()
        player = nil
        looper = nil

        setupVideoPlayer(url: newURL)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            videoState = .playingAnnotated(newURL)
            print("   ✅ Now playing annotated video")
            print("🎬 [CoachPage] ========== OVERLAY SWAP COMPLETE ==========")
        }
    }

    func setupVideoPlayer(url: URL) {
        guard player == nil else {
            print("🎬 [CoachPage] Player already exists, skipping setup")
            return
        }

        print("🎬 [CoachPage] Setting up video player")
        print("   URL: \(url.lastPathComponent)")

        let asset = AVAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        queuePlayer.isMuted = true
        queuePlayer.play()
        player = queuePlayer
        isVideoPlaying = true

        print("🎬 [CoachPage] ✅ Video player ready, looping enabled")
    }

    // MARK: - Backend Landmarks JSON → SkeletonSyncController

    func loadLandmarksIfAvailable() {
        guard let url = liveDelivery.landmarksURL, let p = player else { return }
        guard skeletonSyncController == nil else { return }  // Already loaded
        Task { await loadLandmarksFromURL(url, player: p) }
    }

    func loadLandmarksFromURL(_ url: URL, player: AVPlayer) async {
        print("🦴 [CoachPage] Downloading landmarks JSON: \(url.lastPathComponent)")
        isLoadingPoseData = true
        defer { isLoadingPoseData = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let landmarksData = try JSONDecoder().decode(LandmarksData.self, from: data)
            let frames = landmarksData.toFramePoseLandmarks()
            let expertAnalysis = ExpertAnalysisBuilder.build(from: phases)
            skeletonSyncController = SkeletonSyncController(
                player: player,
                frames: frames,
                expertAnalysis: expertAnalysis
            )
            print("🦴 [CoachPage] ✅ Skeleton sync ready — \(frames.count) frames from backend JSON")
        } catch {
            print("🦴 [CoachPage] ❌ Failed to load landmarks: \(error)")
        }
    }
}
