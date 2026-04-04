import AVKit
import SwiftUI

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
            Color.black.ignoresSafeArea()

            if clips.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0, green: 0.427, blue: 0.467).opacity(0.5))
                    Text("No saved clips yet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Mark release & arrival, then\ntap Clip & Save or Save Full.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(clips) { clip in
                            clipCard(clip)
                                .onTapGesture {
                                    selectedClip = clip
                                    showPlayer = true
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        ClipStore.shared.delete(clip.id)
                                        reload()
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
        .navigationTitle("My Clips")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(isPresented: $showPlayer) {
            if let clip = selectedClip {
                clipPlayer(clip)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        clips = ClipStore.shared.loadAll()
    }

    // MARK: - Card

    private func clipCard(_ clip: SavedClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let thumbURL = clip.thumbnailURL,
                   let img = UIImage(contentsOfFile: thumbURL.path) {
                    Image(uiImage: img)
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
                        Text("\(Int(clip.durationSeconds))s")
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
                                    : Color.orange
                                )
                            )
                        Spacer()
                    }
                    .padding(6)
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let kmh = clip.speedKMH {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", kmh))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(SpeedCategory.from(kmh: kmh).color)
                    Text("km/h")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                }
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

    // MARK: - Player

    private func clipPlayer(_ clip: SavedClip) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if FileManager.default.fileExists(atPath: clip.clipURL.path) {
                VideoPlayer(player: AVPlayer(url: clip.clipURL))
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button { showPlayer = false } label: {
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
    }
}
