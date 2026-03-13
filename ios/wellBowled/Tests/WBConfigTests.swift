import XCTest
@testable import wellBowled

final class WBConfigTests: XCTestCase {

    // MARK: - Persona Properties

    func testAllPersonasHaveLabels() {
        for persona in WBConfig.MatePersona.allCases {
            XCTAssertFalse(persona.label.isEmpty, "\(persona.rawValue) has empty label")
        }
    }

    func testPersonaGenderSplit() {
        let males = WBConfig.MatePersona.allCases.filter(\.isMale)
        let females = WBConfig.MatePersona.allCases.filter { !$0.isMale }

        XCTAssertEqual(males.count, 4, "Expected 4 male personas")
        XCTAssertEqual(females.count, 4, "Expected 4 female personas")
    }

    func testMalePersonasUseAchirdVoice() {
        for persona in WBConfig.MatePersona.allCases where persona.isMale {
            XCTAssertEqual(persona.voiceName, "Achird", "\(persona.rawValue) should use Achird")
        }
    }

    func testFemalePersonasUseAoedeVoice() {
        for persona in WBConfig.MatePersona.allCases where !persona.isMale {
            XCTAssertEqual(persona.voiceName, "Aoede", "\(persona.rawValue) should use Aoede")
        }
    }

    func testPersonaTTSLanguages() {
        XCTAssertEqual(WBConfig.MatePersona.aussieMale.ttsLanguage, "en-AU")
        XCTAssertEqual(WBConfig.MatePersona.aussieFemale.ttsLanguage, "en-AU")
        XCTAssertEqual(WBConfig.MatePersona.englishMale.ttsLanguage, "en-US")
        XCTAssertEqual(WBConfig.MatePersona.englishFemale.ttsLanguage, "en-US")
        XCTAssertEqual(WBConfig.MatePersona.tamilMale.ttsLanguage, "ta-IN")
        XCTAssertEqual(WBConfig.MatePersona.tamilFemale.ttsLanguage, "ta-IN")
        XCTAssertEqual(WBConfig.MatePersona.tanglishMale.ttsLanguage, "en-IN")
        XCTAssertEqual(WBConfig.MatePersona.tanglishFemale.ttsLanguage, "en-IN")
    }

    func testPersonaStyleMapping() {
        XCTAssertEqual(WBConfig.MatePersona.aussieMale.personaStyle, .aussie)
        XCTAssertEqual(WBConfig.MatePersona.englishFemale.personaStyle, .english)
        XCTAssertEqual(WBConfig.MatePersona.tamilMale.personaStyle, .tamil)
        XCTAssertEqual(WBConfig.MatePersona.tanglishFemale.personaStyle, .tanglish)
    }

    // MARK: - System Instruction

    func testSystemInstructionContainsBaseContent() {
        // Test all persona styles produce instructions containing the base
        for persona in WBConfig.MatePersona.allCases {
            // Temporarily set persona
            let oldRaw = UserDefaults.standard.string(forKey: "mate_persona")
            UserDefaults.standard.set(persona.rawValue, forKey: "mate_persona")

            let instruction = WBConfig.mateSystemInstruction
            XCTAssertTrue(instruction.contains("expert cricket mate"), "\(persona.rawValue) instruction missing base content")
            XCTAssertTrue(instruction.contains("STYLE"), "\(persona.rawValue) instruction missing style section")

            // Restore
            UserDefaults.standard.set(oldRaw, forKey: "mate_persona")
        }
    }

    // MARK: - Default Persona

    func testDefaultPersonaIsAussieMale() {
        XCTAssertEqual(WBConfig.MatePersona.defaultPersona, .aussieMale)
    }

    func testInvalidPersonaRawValueFallsToDefault() {
        let persona = WBConfig.MatePersona(rawValue: "invalid_persona")
        XCTAssertNil(persona, "Invalid raw value should return nil")
    }

    // MARK: - Config Constants

    func testDetectionThresholdsAreReasonable() {
        XCTAssertGreaterThan(WBConfig.wristVelocityThreshold, 0)
        XCTAssertGreaterThan(WBConfig.deliveryCooldown, 0)
    }

    func testClipTimingsArePositive() {
        XCTAssertGreaterThan(WBConfig.clipPreRoll, 0)
        XCTAssertGreaterThan(WBConfig.clipPostRoll, 0)
    }

    func testDeliveryDetectionSegmentConfigProducesPositiveStride() {
        XCTAssertGreaterThan(WBConfig.deliveryDetectionSegmentDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(WBConfig.deliveryDetectionSegmentOverlapSeconds, 0)
        XCTAssertLessThan(WBConfig.deliveryDetectionSegmentOverlapSeconds, WBConfig.deliveryDetectionSegmentDurationSeconds)
        XCTAssertGreaterThan(WBConfig.deliveryDetectionSegmentStrideSeconds, 0)
        XCTAssertEqual(
            WBConfig.deliveryDetectionSegmentStrideSeconds,
            WBConfig.deliveryDetectionSegmentDurationSeconds - WBConfig.deliveryDetectionSegmentOverlapSeconds,
            accuracy: 0.0001
        )
    }

    func testFallbackDeliveryDetectionSegmentConfigProducesPositiveStride() {
        XCTAssertGreaterThan(WBConfig.deliveryDetectionFallbackSegmentDurationSeconds, 0)
        XCTAssertGreaterThanOrEqual(WBConfig.deliveryDetectionFallbackSegmentOverlapSeconds, 0)
        XCTAssertLessThan(WBConfig.deliveryDetectionFallbackSegmentOverlapSeconds, WBConfig.deliveryDetectionFallbackSegmentDurationSeconds)
        XCTAssertGreaterThan(WBConfig.deliveryDetectionFallbackSegmentStrideSeconds, 0)
        XCTAssertEqual(
            WBConfig.deliveryDetectionFallbackSegmentStrideSeconds,
            WBConfig.deliveryDetectionFallbackSegmentDurationSeconds - WBConfig.deliveryDetectionFallbackSegmentOverlapSeconds,
            accuracy: 0.0001
        )
    }

    func testDeliveryMergeWindowIsReasonable() {
        XCTAssertGreaterThan(WBConfig.deliveryDetectionMergeWindowSeconds, 0)
        XCTAssertLessThanOrEqual(WBConfig.deliveryDetectionMergeWindowSeconds, 2.0)
    }

    func testLiveAPIFrameRateIsReasonable() {
        XCTAssertGreaterThanOrEqual(WBConfig.liveAPIFrameRate, 1.0)
        XCTAssertLessThanOrEqual(WBConfig.liveAPIFrameRate, 10.0)
    }

    func testCameraCaptureConfigIsReasonable() {
        XCTAssertGreaterThanOrEqual(WBConfig.cameraTargetFPS, 24)
        XCTAssertGreaterThanOrEqual(WBConfig.cameraMaxFPS, WBConfig.cameraTargetFPS)
        XCTAssertGreaterThan(WBConfig.cameraFallbackFPS, 0)
        XCTAssertLessThanOrEqual(WBConfig.cameraFallbackFPS, WBConfig.cameraMaxFPS)
        XCTAssertGreaterThan(WBConfig.cameraPreferredMinWidth, 0)
        XCTAssertGreaterThan(WBConfig.cameraPreferredMinHeight, 0)
    }

    func testLiveAPIVoiceDerivedFromPersona() {
        let oldRaw = UserDefaults.standard.string(forKey: "mate_persona")

        UserDefaults.standard.set("aussie_male", forKey: "mate_persona")
        XCTAssertEqual(WBConfig.liveAPIVoice, "Achird")

        UserDefaults.standard.set("aussie_female", forKey: "mate_persona")
        XCTAssertEqual(WBConfig.liveAPIVoice, "Aoede")

        UserDefaults.standard.set(oldRaw, forKey: "mate_persona")
    }

    func testLiveSessionTimeoutIsThreeMinutes() {
        XCTAssertEqual(WBConfig.liveSessionMaxDurationSeconds, 180)
    }

    func testGenerateContentURLUsesModelAndConfiguredKey() {
        let oldKey = UserDefaults.standard.string(forKey: "gemini_api_key")
        WBConfig.geminiAPIKey = "unit_test_key_123"
        defer { UserDefaults.standard.set(oldKey, forKey: "gemini_api_key") }

        let url = WBConfig.generateContentURL(model: "gemini-2.5-flash")
        let value = url.absoluteString
        XCTAssertTrue(value.contains("/models/gemini-2.5-flash:generateContent"))
        XCTAssertTrue(value.contains("key=unit_test_key_123"))
    }

    func testGeminiAPIKeyFallsBackWhenUserDefaultMissing() {
        let oldKey = UserDefaults.standard.string(forKey: "gemini_api_key")
        UserDefaults.standard.removeObject(forKey: "gemini_api_key")
        defer { UserDefaults.standard.set(oldKey, forKey: "gemini_api_key") }

        XCTAssertTrue(WBConfig.hasAPIKey)
        XCTAssertFalse(WBConfig.geminiAPIKey.isEmpty)
    }

    func testMatePersonaGetterSetterRoundTrip() {
        let oldRaw = UserDefaults.standard.string(forKey: "mate_persona")
        defer { UserDefaults.standard.set(oldRaw, forKey: "mate_persona") }

        WBConfig.matePersona = .tanglishFemale
        XCTAssertEqual(WBConfig.matePersona, .tanglishFemale)
        XCTAssertEqual(WBConfig.ttsLanguage, "en-IN")
    }

    func testMateSystemInstructionIncludesStyleSpecificCues() {
        let oldRaw = UserDefaults.standard.string(forKey: "mate_persona")
        defer { UserDefaults.standard.set(oldRaw, forKey: "mate_persona") }

        UserDefaults.standard.set(WBConfig.MatePersona.aussieMale.rawValue, forKey: "mate_persona")
        XCTAssertTrue(WBConfig.mateSystemInstruction.contains("casual Australian English"))

        UserDefaults.standard.set(WBConfig.MatePersona.englishFemale.rawValue, forKey: "mate_persona")
        XCTAssertTrue(WBConfig.mateSystemInstruction.contains("clear, standard English"))

        UserDefaults.standard.set(WBConfig.MatePersona.tamilMale.rawValue, forKey: "mate_persona")
        XCTAssertTrue(WBConfig.mateSystemInstruction.contains("SPEAK ENTIRELY IN TAMIL"))

        UserDefaults.standard.set(WBConfig.MatePersona.tanglishFemale.rawValue, forKey: "mate_persona")
        XCTAssertTrue(WBConfig.mateSystemInstruction.contains("Speak in Tanglish"))
    }
}
