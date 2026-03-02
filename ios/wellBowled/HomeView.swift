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
    @State private var selectedMode: SessionMode = .freePlay

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.051, green: 0.067, blue: 0.09).ignoresSafeArea()

                VStack(spacing: 32) {
                    Spacer()

                    CricketBallMark(size: 100)

                    Text("wellBowled")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)

                    Text("Real-time bowling feedback with Gemini Live")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Spacer()

                    if hasKey {
                        Picker("Mode", selection: $selectedMode) {
                            Text("Free Play").tag(SessionMode.freePlay)
                            Text("Challenge").tag(SessionMode.challenge)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 8)

                        Button {
                            showSession = true
                        } label: {
                            Label(startButtonTitle, systemImage: "mic.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(red: 0, green: 0.427, blue: 0.467))
                                .cornerRadius(16)
                        }
                    } else {
                        Button {
                            showAPIKeyPrompt = true
                        } label: {
                            Label("Add Gemini API Key", systemImage: "key.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange)
                                .cornerRadius(16)
                        }

                        Text("One-time setup. Your key stays on this device.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    // Settings
                    if hasKey {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
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
            LiveSessionView(initialMode: selectedMode)
        }
        .sheet(isPresented: $showSettings) {
            MateSettingsView(selectedPersona: $selectedPersona, showAPIKeyPrompt: $showAPIKeyPrompt)
        }
        .onAppear {
            hasKey = WBConfig.hasAPIKey
        }
    }

    private var startButtonTitle: String {
        selectedMode == .challenge ? "Start Live Challenge" : "Start Live Coaching"
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
