import PhotosUI
import SwiftUI
import os

private let log = Logger(subsystem: "com.wellbowled", category: "HomeView")

/// Step 1 entry point: single button to start a Live API voice session.
struct HomeView: View {
    @State private var showAPIKeyPrompt = false
    @State private var apiKeyInput = ""
    @State private var hasKey = WBConfig.hasAPIKey
    @State private var showSettings = false
    @State private var showSession = false
    @State private var selectedPersona = WBConfig.matePersona
    @State private var selectedRecordingItem: PhotosPickerItem?
    @State private var isImportingRecording = false
    @State private var recordingImportError: String?
    @State private var importedRecordingURL: URL?
    @State private var showImportedReplay = false

    var body: some View {
        NavigationStack {
            ZStack {
                homeBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerBar
                        heroCard

                        if hasKey {
                            modeSelectionCard
                            startButton
                            recordingPickerButton

                            if let recordingImportError {
                                Text(recordingImportError)
                                    .font(.caption)
                                    .foregroundColor(Color(hex: "F4A261"))
                                    .padding(.horizontal, 4)
                            }
                        } else {
                            apiKeyCard
                        }

                        valueProps
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .alert("Connect Gemini", isPresented: $showAPIKeyPrompt) {
            TextField("Paste Gemini API key", text: $apiKeyInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save") {
                let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    WBConfig.geminiAPIKey = trimmed
                    hasKey = true
                    log.debug("API key saved (\(trimmed.prefix(8))...)")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste your Google AI Studio Gemini key to enable live session audio + video feedback.")
        }
        .fullScreenCover(isPresented: $showSession) {
            LiveSessionView()
        }
        .fullScreenCover(isPresented: $showImportedReplay, onDismiss: {
            importedRecordingURL = nil
        }) {
            if let importedRecordingURL {
                ImportedSessionReplayContainer(
                    recordingURL: importedRecordingURL,
                    mode: .freePlay
                )
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showSettings) {
            MateSettingsView(selectedPersona: $selectedPersona, showAPIKeyPrompt: $showAPIKeyPrompt)
        }
        .onAppear {
            hasKey = WBConfig.hasAPIKey
        }
        .onChange(of: selectedRecordingItem) { _, newItem in
            guard let newItem else { return }
            Task { await importRecording(from: newItem) }
        }
    }

    private var startButtonTitle: String {
        "Start Live Session"
    }

    private var homeBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "060B12"), Color(hex: "0D1C26"), Color(hex: "0B0F16")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(hex: "20C997").opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 40)
                .offset(x: -120, y: -280)

            Circle()
                .fill(Color(hex: "F4A261").opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 36)
                .offset(x: 130, y: -180)
        }
    }

    private var headerBar: some View {
        HStack {
            Label(hasKey ? "API Connected" : "Setup Needed", systemImage: hasKey ? "checkmark.seal.fill" : "key.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(hasKey ? Color(hex: "20C997") : Color(hex: "F4A261"))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )

            Spacer()

            if hasKey {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CricketBallMark(size: 74)

            Text("wellBowled")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Your AI bowling mate with Gemini voice feedback, smart delivery capture, and deep phase analysis.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.78))
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private var modeSelectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Expert Mate")
                .font(.headline)
                .foregroundColor(.white)

            Text("Your AI bowling buddy observes, challenges, and debriefs — all through voice.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var startButton: some View {
        Button {
            showSession = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.headline)
                Text(startButtonTitle)
                    .font(.headline.weight(.semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "20C997"), Color(hex: "6EE7C8")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }

    private var recordingPickerButton: some View {
        PhotosPicker(selection: $selectedRecordingItem, matching: .videos, photoLibrary: .shared()) {
            HStack(spacing: 10) {
                if isImportingRecording {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.headline)
                }

                Text(isImportingRecording ? "Importing recording..." : "Use iPhone Recording")
                    .font(.headline.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isImportingRecording)
    }

    private var apiKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Gemini API")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add your API key once. It stays on this device and unlocks your live voice + video buddy.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.75))
                .lineSpacing(2)

            Button {
                showAPIKeyPrompt = true
            } label: {
                Label("Add Gemini API Key", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: "F4A261"))
                    )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueRow(icon: "bolt.fill", text: "Low-latency live feedback in under 1 second response loops.")
            valueRow(icon: "film.stack.fill", text: "Auto-captured delivery clips with deep on-demand analysis.")
            valueRow(icon: "figure.cricket", text: "Action-signature DNA matching against iconic bowlers.")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func valueRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(Color(hex: "20C997"))
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func importRecording(from item: PhotosPickerItem) async {
        isImportingRecording = true
        recordingImportError = nil
        log.debug("Home recording import started")
        defer { isImportingRecording = false }

        do {
            guard let movie = try await item.loadTransferable(type: MovieFile.self) else {
                recordingImportError = "Could not load selected recording."
                selectedRecordingItem = nil
                return
            }

            importedRecordingURL = movie.url
            showImportedReplay = true
            selectedRecordingItem = nil
            log.debug("Home recording import completed: \(movie.url.lastPathComponent, privacy: .public)")
        } catch {
            selectedRecordingItem = nil
            recordingImportError = "Import failed: \(error.localizedDescription)"
            log.error("Home recording import failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

private struct ImportedSessionReplayContainer: View {
    let recordingURL: URL
    let mode: SessionMode

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SessionViewModel()
    @State private var didPrepareReplay = false

    var body: some View {
        SessionResultsView(
            viewModel: viewModel,
            onExitToHome: { dismiss() }
        )
        .onAppear {
            guard !didPrepareReplay else { return }
            didPrepareReplay = true
            Task {
                await viewModel.prepareImportedSessionReplay(
                    recordingURL: recordingURL,
                    mode: mode
                )
            }
        }
        .onDisappear {
            viewModel.cancelReplayPreparation()
        }
    }
}

// MARK: - Settings

struct MateSettingsView: View {
    @Binding var selectedPersona: WBConfig.MatePersona
    @Binding var showAPIKeyPrompt: Bool
    @Environment(\.dismiss) private var dismiss

    private let personaGroups: [(title: String, male: WBConfig.MatePersona, female: WBConfig.MatePersona)] = [
        ("Aussie Mate", .aussieMale, .aussieFemale),
        ("English", .englishMale, .englishFemale),
        ("தமிழ் (Tamil)", .tamilMale, .tamilFemale),
        ("Tanglish", .tanglishMale, .tanglishFemale),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Mate Persona") {
                    ForEach(personaGroups, id: \.title) { group in
                        HStack {
                            Text(group.title)
                                .foregroundColor(.primary)

                            Spacer()

                            // Male button
                            Button {
                                selectedPersona = group.male
                                WBConfig.matePersona = group.male
                            } label: {
                                Image(systemName: "person.fill")
                                    .font(.body)
                                    .foregroundColor(selectedPersona == group.male ? .white : .gray)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle().fill(selectedPersona == group.male ? Color.blue.opacity(0.7) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)

                            // Female button
                            Button {
                                selectedPersona = group.female
                                WBConfig.matePersona = group.female
                            } label: {
                                Image(systemName: "person.fill")
                                    .font(.body)
                                    .foregroundColor(selectedPersona == group.female ? .white : .gray)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle().fill(selectedPersona == group.female ? Color.pink.opacity(0.7) : Color.clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        showAPIKeyPrompt = true
                    } label: {
                        Label("Change API Key", systemImage: "key.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
