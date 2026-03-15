import AVFoundation
import Combine
import Foundation
import os
import UIKit

private let log = Logger(subsystem: "com.wellbowled", category: "GeminiLive")

// MARK: - Connection State

enum LiveConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Wire Protocol Structs (Outbound)

struct LiveSetupMessage: Encodable {
    let setup: LiveSetupConfig
}

struct LiveSetupConfig: Encodable {
    let model: String
    let generationConfig: LiveGenerationConfig
    let systemInstruction: LiveSystemInstruction
    let outputAudioTranscription: LiveOutputAudioTranscription
    let contextWindowCompression: LiveContextWindowCompression
    let tools: [LiveTool]
    let sessionResumption: LiveSessionResumption?
}

struct LiveSessionResumption: Encodable {
    let handle: String
}

struct LiveGenerationConfig: Encodable {
    let responseModalities: [String]
    let speechConfig: LiveSpeechConfig
}

struct LiveSpeechConfig: Encodable {
    let voiceConfig: LiveVoiceConfig
}

struct LiveVoiceConfig: Encodable {
    let prebuiltVoiceConfig: PrebuiltVoiceConfig
}

struct PrebuiltVoiceConfig: Encodable {
    let voiceName: String
}

struct LiveSystemInstruction: Encodable {
    let parts: [LiveTextPart]
}

struct LiveTextPart: Encodable {
    let text: String
}

struct LiveOutputAudioTranscription: Encodable {}

struct LiveContextWindowCompression: Encodable {
    let triggerTokens: Int
    let slidingWindow: LiveSlidingWindow
}

struct LiveSlidingWindow: Encodable {
    let targetTokens: Int
}

struct LiveTool: Encodable {
    let functionDeclarations: [LiveFunctionDeclaration]
}

struct LiveFunctionDeclaration: Encodable {
    let name: String
    let description: String
    let parameters: LiveFunctionParameters
}

struct LiveFunctionParameters: Encodable {
    let type: String
    let properties: [String: LiveFunctionProperty]
    let required: [String]
}

struct LiveFunctionProperty: Encodable {
    let type: String
    let description: String
    let `enum`: [String]?
}

struct LiveRealtimeInput: Encodable {
    let realtimeInput: LiveMediaInput
}

struct LiveMediaInput: Encodable {
    let mediaChunks: [LiveMediaChunk]
}

struct LiveMediaChunk: Encodable {
    let mimeType: String
    let data: String
}

struct LiveClientContent: Encodable {
    let clientContent: LiveClientTurn
}

struct LiveClientTurn: Encodable {
    let turns: [LiveTurn]
    let turnComplete: Bool
}

struct LiveTurn: Encodable {
    let role: String
    let parts: [LiveTextPart]
}

struct LiveToolResponseMessage: Encodable {
    let toolResponse: LiveToolResponse
}

struct LiveToolResponse: Encodable {
    let functionResponses: [LiveFunctionResponse]
}

struct LiveFunctionResponse: Encodable {
    let id: String?
    let name: String
    let response: LiveFunctionResponsePayload
}

struct LiveFunctionResponsePayload: Encodable {
    let message: String
}

// MARK: - Wire Protocol Structs (Inbound)

struct LiveServerMessage: Decodable {
    let setupComplete: LiveSetupComplete?
    let serverContent: LiveServerContent?
    let toolCall: LiveToolCall?
    let goAway: LiveGoAway?
    let sessionResumptionUpdate: LiveSessionResumptionUpdate?
}

struct LiveSetupComplete: Decodable {}

struct LiveServerContent: Decodable {
    let modelTurn: LiveModelTurn?
    let outputTranscription: LiveTranscription?
    let inputTranscription: LiveTranscription?
    let turnComplete: Bool?
}

struct LiveToolCall: Decodable {
    let functionCalls: [LiveFunctionCall]
}

struct LiveFunctionCall: Decodable {
    let id: String?
    let name: String
    let args: [String: String]
}

struct LiveModelTurn: Decodable {
    let parts: [LiveContentPart]
}

struct LiveContentPart: Decodable {
    let inlineData: LiveInlineData?
    let text: String?
}

struct LiveInlineData: Decodable {
    let mimeType: String
    let data: String
}

struct LiveTranscription: Decodable {
    let text: String
}

struct LiveGoAway: Decodable {
    let timeLeft: String?
}

struct LiveSessionResumptionUpdate: Decodable {
    let newHandle: String?
}

// MARK: - GeminiLiveService

final class GeminiLiveService: NSObject, VoiceMateService {

    // MARK: - VoiceMateService

    weak var delegate: VoiceMateDelegate?
    private(set) var isConnected: Bool = false
    private(set) var isSpeaking: Bool = false

    /// Observable connection state for UI
    @Published var connectionState: LiveConnectionState = .disconnected

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let sendQueue = DispatchQueue(label: "com.wellbowled.live.send")
    private var receiveTask: Task<Void, Never>?
    private var lastFrameSentTime: CFAbsoluteTime = 0
    private var sessionResumptionHandle: String?
    private var openContinuation: CheckedContinuation<Void, Error>?
    private let continuationLock = NSLock()  // Protect openContinuation from concurrent delegate callbacks

    // Google AI Live API expects camelCase keys — do NOT use .convertToSnakeCase
    private let encoder = JSONEncoder()

    // Server sends camelCase — match directly, no conversion needed
    private let decoder = JSONDecoder()

    private static let mateTools: [LiveTool] = [
        LiveTool(
            functionDeclarations: [
                LiveFunctionDeclaration(
                    name: "end_session",
                    description: "End the bowling session when the player asks to stop or time is up.",
                    parameters: LiveFunctionParameters(
                        type: "OBJECT",
                        properties: [
                            "reason": LiveFunctionProperty(
                                type: "STRING",
                                description: "Why the session is ending",
                                enum: nil
                            )
                        ],
                        required: ["reason"]
                    )
                )
            ]
        )
    ]

    // MARK: - Connect

    func connect() async throws {
        guard !isConnected else {
            log.debug("connect() called but already connected, skipping")
            return
        }

        let apiKey = WBConfig.geminiAPIKey
        guard !apiKey.isEmpty else {
            log.error("No API key configured")
            await updateState(.error("No API key configured"))
            throw LiveAPIError.noAPIKey
        }
        print("[GeminiLive] API key present (\(apiKey.prefix(8))...)")

        await updateState(.connecting)

        let urlString = "\(WBConfig.liveAPIEndpoint)?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            log.error("Invalid endpoint URL: \(urlString)")
            await updateState(.error("Invalid endpoint URL"))
            throw LiveAPIError.invalidURL
        }
        print("[GeminiLive] Connecting to \(url.host ?? "unknown")...")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task

        // Fix race condition: set continuation BEFORE resuming task.
        // task.resume() inside the closure guarantees openContinuation is set
        // before didOpen can fire.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    self.continuationLock.lock()
                    self.openContinuation = continuation
                    self.continuationLock.unlock()
                    task.resume()  // Start connection AFTER continuation is stored
                    print("[GeminiLive] WebSocket task resumed, continuation ready")
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15s timeout
                throw LiveAPIError.connectionTimeout
            }
            try await group.next()
            group.cancelAll()
        }
        print("[GeminiLive] WebSocket open confirmed")

        // Send setup message
        try await sendSetup()
        print("[GeminiLive] Setup sent, starting receive loop")

        // Start receive loop — setupComplete handled inside
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        log.debug("Disconnecting...")
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        isSpeaking = false
        await updateState(.disconnected)
        delegate?.voiceMate(didChangeConnectionState: false)
        log.debug("Disconnected")
    }

    // MARK: - Send Video Frame

    func sendVideoFrame(_ jpegData: Data) {
        // Only send after setupComplete — sending before isConnected causes server to close
        guard isConnected else { return }

        let now = CFAbsoluteTimeGetCurrent()
        let interval = 1.0 / WBConfig.liveAPIFrameRate
        guard now - lastFrameSentTime >= interval else { return }
        lastFrameSentTime = now

        // Resize + compress on background
        sendQueue.async { [weak self] in
            guard let self, let resized = self.resizeJPEG(jpegData) else { return }
            let base64 = resized.base64EncodedString()
            let input = LiveRealtimeInput(
                realtimeInput: LiveMediaInput(
                    mediaChunks: [LiveMediaChunk(mimeType: "image/jpeg", data: base64)]
                )
            )
            self.sendJSON(input)
        }
    }

    // MARK: - Send Audio

    func sendAudio(_ pcmData: Data) {
        // Only send after setupComplete — sending before isConnected causes server to close
        guard isConnected else { return }

        sendQueue.async { [weak self] in
            guard let self else { return }
            let base64 = pcmData.base64EncodedString()
            let input = LiveRealtimeInput(
                realtimeInput: LiveMediaInput(
                    mediaChunks: [LiveMediaChunk(mimeType: "audio/pcm;rate=16000", data: base64)]
                )
            )
            self.sendJSON(input)
        }
    }

    // MARK: - Send Context

    func sendContext(_ text: String) async {
        let content = LiveClientContent(
            clientContent: LiveClientTurn(
                turns: [LiveTurn(role: "user", parts: [LiveTextPart(text: text)])],
                turnComplete: true
            )
        )
        sendJSON(content)
    }

    func speakChallenge(target: String) async {
        await sendContext(
            """
            Challenge mode: tell the bowler this target now in one short sentence.
            Target: \(target)
            """
        )
    }

    // MARK: - Setup

    private func sendSetup() async throws {
        // Include session resumption handle on reconnect to restore conversation context
        let resumption = sessionResumptionHandle.map { LiveSessionResumption(handle: $0) }
        if resumption != nil {
            log.info("Sending session resumption handle on reconnect")
        }

        let setup = LiveSetupMessage(
            setup: LiveSetupConfig(
                model: WBConfig.liveAPIModel,
                generationConfig: LiveGenerationConfig(
                    responseModalities: ["AUDIO"],
                    speechConfig: LiveSpeechConfig(
                        voiceConfig: LiveVoiceConfig(
                            prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: WBConfig.liveAPIVoice)
                        )
                    )
                ),
                systemInstruction: LiveSystemInstruction(
                    parts: [LiveTextPart(text: WBConfig.mateSystemInstruction)]
                ),
                outputAudioTranscription: LiveOutputAudioTranscription(),
                contextWindowCompression: LiveContextWindowCompression(
                    triggerTokens: 25600,
                    slidingWindow: LiveSlidingWindow(targetTokens: 12800)
                ),
                tools: Self.mateTools,
                sessionResumption: resumption
            )
        )

        guard let data = try? encoder.encode(setup),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw LiveAPIError.encodingFailed
        }

        try await webSocketTask?.send(.string(jsonString))
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        guard let ws = webSocketTask else {
            print("[GeminiLive] receiveLoop: no webSocketTask")
            return
        }

        print("[GeminiLive] receiveLoop started, state=\(ws.state.rawValue)")
        var messageCount = 0

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                messageCount += 1
                switch message {
                case .string(let text):
                    print("[GeminiLive] MSG #\(messageCount) string (\(text.count) chars): \(text.prefix(120))")
                    handleMessage(text)
                case .data(let data):
                    print("[GeminiLive] MSG #\(messageCount) data (\(data.count) bytes)")
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    print("[GeminiLive] MSG #\(messageCount) unknown type")
                }
            } catch {
                if !Task.isCancelled {
                    print("[GeminiLive] Receive error after \(messageCount) messages: \(error)")
                    log.error("Receive error after \(messageCount) msgs: \(error.localizedDescription)")
                    await updateState(.error(error.localizedDescription))
                    delegate?.voiceMate(didChangeConnectionState: false)
                    isConnected = false
                }
                break
            }
        }
        print("[GeminiLive] receiveLoop ended (messages received: \(messageCount))")
    }

    private func handleMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let msg = try? decoder.decode(LiveServerMessage.self, from: data) else {
            // Surface undecodable server messages — often contains the actual error
            let preview = String(jsonString.prefix(200))
            log.warning("Failed to decode message: \(preview)")
            print("[GeminiLive] UNDECODABLE MSG: \(preview)")
            delegate?.voiceMate(didDisconnect: "Server: \(preview)")
            return
        }

        // Setup complete
        if msg.setupComplete != nil {
            isConnected = true
            Task { @MainActor in
                connectionState = .connected
            }
            delegate?.voiceMate(didChangeConnectionState: true)
            log.info("Setup complete — connected to Live API")
        }

        // Server content (audio, transcription, turn)
        if let content = msg.serverContent {
            // Audio data
            if let turn = content.modelTurn {
                isSpeaking = true
                let chunkCount = turn.parts.filter { $0.inlineData != nil }.count
                log.debug("Audio turn: \(chunkCount) chunk(s)")
                for part in turn.parts {
                    if let inlineData = part.inlineData,
                       inlineData.mimeType.contains("audio"),
                       let audioData = Data(base64Encoded: inlineData.data) {
                        log.debug("Playing audio chunk: \(audioData.count) bytes (\(inlineData.mimeType))")
                        delegate?.voiceMate(didReceiveAudio: audioData)
                    }
                }
            }

            // Transcription
            if let transcription = content.outputTranscription {
                log.debug("Transcript: \(transcription.text.prefix(80))")
                delegate?.voiceMate(didTranscribe: transcription.text)
            }

            // User input transcription
            if let userTranscription = content.inputTranscription {
                log.debug("User transcript: \(userTranscription.text.prefix(80))")
                delegate?.voiceMate(didTranscribeUser: userTranscription.text)
            }

            // Turn complete
            if content.turnComplete == true {
                isSpeaking = false
                log.debug("Turn complete")
                delegate?.voiceMateDidFinishTurn()
            }
        }

        // Tool calls (model-driven mode switching)
        if let toolCall = msg.toolCall {
            handleToolCall(toolCall)
        }

        // Session resumption
        if let resumption = msg.sessionResumptionUpdate {
            sessionResumptionHandle = resumption.newHandle
            log.debug("Session handle updated: \(resumption.newHandle ?? "nil")")
        }

        // Go away warning
        if let goAway = msg.goAway {
            log.warning("Server going away: \(goAway.timeLeft ?? "unknown")")
        }
    }

    // MARK: - Helpers

    private func handleToolCall(_ toolCall: LiveToolCall) {
        for functionCall in toolCall.functionCalls {
            switch functionCall.name {
            case "end_session":
                let reason = functionCall.args["reason"] ?? "Player requested"
                Task { [weak self] in
                    guard let self else { return }
                    await self.delegate?.voiceMate(didRequestEndSession: reason)
                    self.sendToolResponse(
                        for: functionCall,
                        message: "Session ending: \(reason)"
                    )
                }
            default:
                sendToolResponse(
                    for: functionCall,
                    message: "Unknown tool: \(functionCall.name)"
                )
            }
        }
    }

    private func sendToolResponse(for functionCall: LiveFunctionCall, message: String) {
        let response = LiveToolResponseMessage(
            toolResponse: LiveToolResponse(
                functionResponses: [
                    LiveFunctionResponse(
                        id: functionCall.id,
                        name: functionCall.name,
                        response: LiveFunctionResponsePayload(message: message)
                    )
                ]
            )
        )
        sendJSON(response)
    }

    /// All sends go through sendQueue to avoid data races on sendCount and serialization.
    private var sendCount = 0

    private func sendJSON<T: Encodable>(_ value: T) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            guard let data = try? self.encoder.encode(value),
                  let jsonString = String(data: data, encoding: .utf8) else {
                print("[GeminiLive] Failed to encode outbound message")
                return
            }

            self.sendCount += 1
            let count = self.sendCount
            let preview = jsonString.prefix(80)
            print("[GeminiLive] SEND #\(count) (\(jsonString.count) chars): \(preview)...")

            self.webSocketTask?.send(.string(jsonString)) { error in
                if let error {
                    print("[GeminiLive] Send #\(count) ERROR: \(error)")
                }
            }
        }
    }

    private func resizeJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        let maxDim = CGFloat(WBConfig.liveAPIMaxFrameDimension)
        let size = image.size

        if size.width <= maxDim && size.height <= maxDim {
            return image.jpegData(compressionQuality: CGFloat(WBConfig.liveAPIJPEGQuality) / 100.0)
        }

        let scale = maxDim / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized?.jpegData(compressionQuality: CGFloat(WBConfig.liveAPIJPEGQuality) / 100.0)
    }

    /// Resume openContinuation exactly once — safe against concurrent delegate callbacks.
    private func resumeContinuation(throwing error: Error? = nil) {
        continuationLock.lock()
        let cont = openContinuation
        openContinuation = nil
        continuationLock.unlock()

        if let cont {
            if let error {
                cont.resume(throwing: error)
            } else {
                cont.resume()
            }
        }
    }

    @MainActor
    private func updateState(_ state: LiveConnectionState) {
        connectionState = state
    }
}

// MARK: - URLSessionWebSocketDelegate

extension GeminiLiveService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        print("[GeminiLive] DELEGATE: didOpen (protocol: \(`protocol` ?? "none"))")
        log.info("WebSocket opened (protocol: \(`protocol` ?? "none"))")
        resumeContinuation()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let summary = reasonStr.isEmpty ? "code \(closeCode.rawValue)" : "code \(closeCode.rawValue): \(reasonStr)"
        print("[GeminiLive] DELEGATE: didClose \(summary)")
        log.info("WebSocket closed: \(summary)")
        isConnected = false
        isSpeaking = false

        // If we were waiting for open, fail the continuation
        resumeContinuation(throwing: LiveAPIError.notConnected)

        Task { @MainActor in
            // Surface close reason so user/debugLog can see why — not just "Disconnected"
            if closeCode == .normalClosure {
                connectionState = .disconnected
            } else {
                connectionState = .error("Server closed (\(summary))")
            }
        }
        delegate?.voiceMate(didDisconnect: summary)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            print("[GeminiLive] DELEGATE: didCompleteWithError: \(error)")
            log.error("URLSession task error: \(error.localizedDescription)")
            resumeContinuation(throwing: error)
            isConnected = false
            Task { @MainActor in
                connectionState = .error(error.localizedDescription)
            }
            delegate?.voiceMate(didDisconnect: error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum LiveAPIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case encodingFailed
    case notConnected
    case connectionTimeout

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No Gemini API key configured"
        case .invalidURL: return "Invalid Live API endpoint"
        case .encodingFailed: return "Failed to encode message"
        case .notConnected: return "Not connected to Live API"
        case .connectionTimeout: return "WebSocket connection timed out (15s)"
        }
    }
}
