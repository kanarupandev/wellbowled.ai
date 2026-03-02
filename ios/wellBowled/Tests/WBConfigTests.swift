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

    func testLiveAPIFrameRateIsReasonable() {
        XCTAssertGreaterThanOrEqual(WBConfig.liveAPIFrameRate, 1.0)
        XCTAssertLessThanOrEqual(WBConfig.liveAPIFrameRate, 10.0)
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
}
