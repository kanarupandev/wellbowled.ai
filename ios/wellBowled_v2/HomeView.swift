import SwiftUI

struct HomeView: View {
    @State private var deliveries: [Delivery] = []
    @State private var showRecord = false
    @State private var showPicker = false
    @State private var showReview = false
    @State private var reviewIndex: Int?

    var body: some View {
        NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 16)

                // Stats bar
                if !deliveries.isEmpty {
                    statsBar
                        .padding(.top, 16)
                }

                // Delivery list
                if deliveries.isEmpty {
                    emptyState
                } else {
                    deliveryList
                }

                Spacer()

                // Action buttons
                actionButtons
                    .padding(.bottom, 30)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ClipsView()
                } label: {
                    Image(systemName: "film.stack")
                        .foregroundColor(Color(red: 0, green: 0.427, blue: 0.467))
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $showRecord) {
            RecordView { delivery in
                deliveries.append(delivery)
                reviewIndex = deliveries.count - 1
            } onDismiss: {
                showRecord = false
                // Auto-open review if a new delivery was just recorded
                if reviewIndex != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showReview = true
                    }
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            VideoPicker { delivery in
                deliveries.append(delivery)
                reviewIndex = deliveries.count - 1
                showPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showReview = true
                }
            }
        }
        .fullScreenCover(isPresented: $showReview) {
            if let idx = reviewIndex, idx < deliveries.count {
                ReviewView(
                    delivery: deliveries[idx],
                    onSave: { release, arrival, distance in
                        deliveries[idx].releaseFrame = release
                        deliveries[idx].arrivalFrame = arrival
                        deliveries[idx].distanceMeters = distance
                    },
                    onDismiss: { showReview = false }
                )
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Image("wellbowled_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 48)

            Text("wellBowled")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("240fps Bowling Speed Analysis")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Stats

    private var statsBar: some View {
        HStack(spacing: 24) {
            statItem("Top", value: bestSpeed.map { String(format: "%.1f", $0) } ?? "—", unit: "km/h",
                     color: bestSpeed.flatMap { SpeedCategory.from(kmh: $0).color } ?? .white)
            statItem("Avg", value: avgSpeed.map { String(format: "%.1f", $0) } ?? "—", unit: "km/h", color: .white)
            statItem("Balls", value: "\(deliveries.count)", unit: "", color: .white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func statItem(_ title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            HStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                if !unit.isEmpty {
                    Text(unit).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "figure.cricket")
                .font(.system(size: 48))
                .foregroundColor(Color(red: 0, green: 0.427, blue: 0.467))
            Text("Record or upload a bowling clip")
                .font(.subheadline)
                .foregroundColor(.gray)
            Text("Mark release and arrival frames to measure speed")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Delivery List

    private var deliveryList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(deliveries.enumerated().reversed()), id: \.element.id) { index, delivery in
                    Button {
                        reviewIndex = index
                        showReview = true
                    } label: {
                        deliveryRow(delivery, number: index + 1)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
        }
    }

    private func deliveryRow(_ delivery: Delivery, number: Int) -> some View {
        HStack {
            Text("#\(number)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1fs @ %.0ffps", delivery.duration, delivery.fps))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)
                Text("\(delivery.totalFrames) frames")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let kmh = delivery.speedKMH, let cat = delivery.category {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", kmh))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(cat.color)
                        Text("km/h")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", delivery.speedMPH ?? 0))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text("mph")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Not measured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button { showRecord = true } label: {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Record")
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(red: 0, green: 0.427, blue: 0.467))
                .cornerRadius(14)
            }

            Button { showPicker = true } label: {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Upload")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.1))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Computed

    private var bestSpeed: Double? { deliveries.compactMap(\.speedKMH).max() }
    private var avgSpeed: Double? {
        let speeds = deliveries.compactMap(\.speedKMH)
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }
}
