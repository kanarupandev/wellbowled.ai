import AVKit
import SwiftUI
import os

private let log = Logger(subsystem: "com.wellbowled", category: "ClipsView")

/// Browsable grid of all saved clips (release-to-end trims and full sessions).
struct ClipsView: View {
    @State private var clips: [SavedClip] = []
    @State private var selectedClip: SavedClip?
    @State private var showPlayer = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ZStack {
            clipsBackground.ignoresSafeArea()

            if clips.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(clips) { clip in
                            ClipCard(clip: clip)
                                .onTapGesture {
                                    selectedClip = clip
                                    showPlayer = true
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteClip(clip)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Clips")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showPlayer) {
            if let clip = selectedClip {
                ClipPlayerView(clip: clip) {
                    showPlayer = false
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        clips = ClipStore.shared.loadAll()
    }

    private func deleteClip(_ clip: SavedClip) {
        ClipStore.shared.delete(clip.id)
        reload()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "20C997").opacity(0.5))
            Text("No saved clips yet")
                .font(.headline)
                .foregroundColor(.white.opacity(0.7))
            Text("After a delivery, tap the save button\nto clip and save it here.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    private var clipsBackground: some View {
        LinearGradient(
            colors: [Color(hex: "060B12"), Color(hex: "0D1C26"), Color(hex: "0B0F16")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Clip Card

private struct ClipCard: View {
    let clip: SavedClip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Thumbnail
            ZStack {
                if let thumbURL = clip.thumbnailURL,
                   let uiImage = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(9/16, contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .aspectRatio(9/16, contentMode: .fill)
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "play.circle")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                        )
                }

                // Duration badge
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(formatDuration(clip.durationSeconds))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                    }
                    .padding(6)
                }

                // Kind badge
                VStack {
                    HStack {
                        Text(clip.kind == .releaseToEnd ? "CLIP" : "FULL")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(
                                    clip.kind == .releaseToEnd
                                    ? Color(red: 0, green: 0.427, blue: 0.467)
                                    : Color(hex: "F4A261")
                                )
                            )
                        Spacer()
                    }
                    .padding(6)
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Meta
            HStack(spacing: 4) {
                if let seq = clip.deliverySequence {
                    Text("Ball \(seq)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                if let kph = clip.speedKph {
                    Text("\(Int(kph)) kph")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(hex: "20C997"))
                }
                Spacer()
            }

            Text(clip.createdAt, style: .date)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.35))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        let min = s / 60
        let sec = s % 60
        if min > 0 { return "\(min):\(String(format: "%02d", sec))" }
        return "\(sec)s"
    }
}

// MARK: - Full-screen Player

private struct ClipPlayerView: View {
    let clip: SavedClip
    let onDismiss: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }

            VStack {
                HStack {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 56)
                Spacer()
            }
        }
        .onAppear {
            let url = clip.clipURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                log.error("Clip file missing: \(url.lastPathComponent, privacy: .public)")
                return
            }
            player = AVPlayer(url: url)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
