import XCTest
@testable import MeadowBattleSupport

final class HealingEffectTierTests: XCTestCase {
    func testTierUsesActualHPGainedAfterClamping() {
        XCTAssertNil(HealingEffectTier.classify(actualHPGained: 0))
        XCTAssertNil(HealingEffectTier.classify(actualHPGained: -4))
        XCTAssertEqual(HealingEffectTier.classify(actualHPGained: 1), .micro)
        XCTAssertEqual(HealingEffectTier.classify(actualHPGained: 3), .micro)
        XCTAssertEqual(HealingEffectTier.classify(actualHPGained: 4), .standard)
        XCTAssertEqual(HealingEffectTier.classify(actualHPGained: 8), .standard)
        XCTAssertEqual(HealingEffectTier.classify(actualHPGained: 9), .strong)
        XCTAssertEqual(HealingEffectTier.classify(actualHPGained: 12), .strong)
    }

    func testTwentyFrameSequenceCrossfadesOnTheSixtyHertzClockAndEndsCleanly() throws {
        let tier = HealingEffectTier.standard
        XCTAssertEqual(HealingEffectTier.duration, 1.0, accuracy: 1e-9)
        let start = try XCTUnwrap(tier.frameBlend(at: 0))
        XCTAssertEqual(start.lower, 0)
        XCTAssertEqual(start.upper, 1)
        XCTAssertEqual(start.upperWeight, 0, accuracy: 1e-9)

        let middle = try XCTUnwrap(tier.frameBlend(at: 0.025))
        XCTAssertEqual(middle.lower, 0)
        XCTAssertEqual(middle.upper, 1)
        XCTAssertEqual(middle.upperWeight, 0.5, accuracy: 1e-9)

        let lastAuthoredFrame = try XCTUnwrap(tier.frameBlend(at: 0.95))
        XCTAssertEqual(lastAuthoredFrame.lower, 19)
        XCTAssertEqual(lastAuthoredFrame.upper, 19)
        XCTAssertNil(tier.frameBlend(at: 1.0))
        XCTAssertNil(tier.frameBlend(at: -0.01))
    }

    func testStrongTierPlacesItsAuthoredGroundEllipseAtRecipientFeet() {
        XCTAssertEqual(HealingEffectTier.micro.canvasGroundAnchorY, 1.0, accuracy: 1e-9)
        XCTAssertEqual(HealingEffectTier.standard.canvasGroundAnchorY, 0.90, accuracy: 1e-9)
        XCTAssertEqual(HealingEffectTier.strong.canvasGroundAnchorY, 0.66, accuracy: 1e-9)
    }

    func testLargerTierProducesMoreEnvironmentalLightAndAllTiersFadeOut() {
        let micro = HealingEffectTier.micro.lightEnvelope(at: 0.30)
        let standard = HealingEffectTier.standard.lightEnvelope(at: 0.30)
        let strong = HealingEffectTier.strong.lightEnvelope(at: 0.30)
        XCTAssertGreaterThan(standard, micro)
        XCTAssertGreaterThan(strong, standard)
        XCTAssertEqual(HealingEffectTier.strong.lightEnvelope(at: 1.0), 0)
    }
}
