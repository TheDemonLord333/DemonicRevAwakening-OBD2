//
//  DemonBrainTests.swift
//  DemonicRevAwakening OBD2Tests
//

import Foundation
import Testing
@testable import DemonicRevAwakening_OBD2

struct DemonBrainTests {
    private let frameTime = 1.0 / 60

    /// Simuliert `seconds` Sekunden mit konstanter Eingabe.
    private func run(_ brain: inout DemonBrain, _ input: DemonInput, seconds: Double) -> DemonFrame {
        var frame = brain.frame
        for _ in 0..<Int(seconds / frameTime) {
            frame = brain.update(input: input, deltaTime: frameTime)
        }
        return frame
    }

    @Test func connectionStatesAreImmediate() {
        var brain = DemonBrain()
        #expect(brain.update(input: .noConnection, deltaTime: frameTime).mood == .disconnected)
        #expect(brain.update(input: .awaitingData, deltaTime: frameTime).mood == .waitingForData)
        let frame = brain.update(input: .awaitingData, deltaTime: frameTime)
        #expect(frame.smoothedRPM == nil)
    }

    @Test(arguments: [
        (0.0, DemonMood.engineOff),
        (780.0, .idle),
        (1_500.0, .awakening),
        (2_800.0, .awake),
        (5_000.0, .unleashed),
    ])
    func moodForSteadyRPM(rpm: Double, expected: DemonMood) {
        var brain = DemonBrain()
        let frame = run(&brain, .rpm(rpm), seconds: 3)
        #expect(frame.mood == expected)
    }

    @Test func engineOffSleepsDeeplyWithClosedEyes() {
        var brain = DemonBrain()
        let frame = run(&brain, .rpm(0), seconds: 4)
        #expect(frame.mood == .engineOff)
        #expect(frame.eyeOpenness < 0.02)
        #expect(frame.energy < 0.02)
    }

    @Test func hysteresisPreventsFlicker() {
        var brain = DemonBrain()
        _ = run(&brain, .rpm(800), seconds: 2)
        #expect(brain.mood == .idle)
        // Schwankung knapp um die Schwelle von 1.000 RPM.
        var moods = Set<DemonMood>()
        for step in 0..<600 {
            let rpm = step.isMultiple(of: 2) ? 960.0 : 1_060.0
            moods.insert(brain.update(input: .rpm(rpm), deltaTime: frameTime).mood)
        }
        #expect(moods == [.idle])
    }

    @Test func dwellTimeDelaysShortSpikes() {
        var brain = DemonBrain()
        // Glättung abschalten, um nur die Mindestverweildauer zu prüfen.
        brain.rpmRiseTau = 0
        brain.rpmFallTau = 0
        _ = run(&brain, .rpm(800), seconds: 2)
        // 0,2 s Spitze ist kürzer als die Verweildauer: kein Zustandswechsel.
        var moods = Set<DemonMood>()
        for _ in 0..<12 { moods.insert(brain.update(input: .rpm(6_000), deltaTime: frameTime).mood) }
        for _ in 0..<120 { moods.insert(brain.update(input: .rpm(800), deltaTime: frameTime).mood) }
        #expect(moods == [.idle])
        // Hält die Drehzahl länger an, folgt der Wechsel.
        #expect(run(&brain, .rpm(6_000), seconds: 1).mood == .unleashed)
    }

    @Test func smoothedSpikeLingersBriefly() {
        var brain = DemonBrain()
        _ = run(&brain, .rpm(800), seconds: 2)
        _ = run(&brain, .rpm(6_000), seconds: 0.2)
        // Nach einer Spitze beruhigt sich der Dämon wieder vollständig.
        #expect(run(&brain, .rpm(800), seconds: 6).mood == .idle)
    }

    @Test func smoothingAvoidsJumps() {
        var brain = DemonBrain()
        _ = run(&brain, .rpm(800), seconds: 2)
        let frame = brain.update(input: .rpm(5_000), deltaTime: frameTime)
        let smoothed = frame.smoothedRPM ?? 0
        #expect(smoothed > 800)
        #expect(smoothed < 1_500)
    }

    @Test func awakensProgressivelyAndFallsAsleepAgain() {
        var brain = DemonBrain()
        let idle = run(&brain, .rpm(800), seconds: 3)
        let awakening = run(&brain, .rpm(1_600), seconds: 3)
        let awake = run(&brain, .rpm(3_000), seconds: 3)
        let unleashed = run(&brain, .rpm(5_500), seconds: 3)
        #expect(idle.eyeOpenness < awakening.eyeOpenness)
        #expect(awakening.eyeOpenness < awake.eyeOpenness)
        #expect(idle.energy < awakening.energy)
        #expect(awakening.energy < awake.energy)
        #expect(awake.energy < unleashed.energy)
        #expect(idle.headLift < awake.headLift)
        #expect(unleashed.mood == .unleashed)

        let calmed = run(&brain, .rpm(800), seconds: 8)
        #expect(calmed.mood == .idle)
        #expect(calmed.eyeOpenness < 0.05)
        #expect(calmed.energy < 0.2)
    }

    @Test func energyIsContinuousAndMonotonic() {
        let brain = DemonBrain()
        var previous = -1.0
        for rpm in stride(from: 0.0, through: 8_000, by: 50) {
            let energy = brain.energy(forRPM: rpm)
            #expect(energy >= previous)
            #expect((0...1).contains(energy))
            #expect(energy - max(previous, 0) < 0.05)
            previous = energy
        }
        #expect(brain.energy(forRPM: 9_000) == 1)
    }

    @Test func fastRiseTriggersSurgeSlowRiseDoesNot() {
        var fast = DemonBrain()
        _ = run(&fast, .rpm(800), seconds: 2)
        let surged = run(&fast, .rpm(3_000), seconds: 0.3)
        #expect(surged.surge > 0.3)

        var slow = DemonBrain()
        _ = run(&slow, .rpm(800), seconds: 2)
        var rpm = 800.0
        var maxSurge = 0.0
        for _ in 0..<600 {
            rpm += 1_000 * frameTime // 1.000 RPM/s
            maxSurge = max(maxSurge, slow.update(input: .rpm(rpm), deltaTime: frameTime).surge)
        }
        #expect(maxSurge == 0)
    }

    @Test func surgeDecays() {
        var brain = DemonBrain()
        _ = run(&brain, .rpm(800), seconds: 2)
        _ = run(&brain, .rpm(3_500), seconds: 0.3)
        let later = run(&brain, .rpm(3_500), seconds: 3)
        #expect(later.surge < 0.01)
    }

    @Test func dataLossResetsSignalWithoutInventingRPM() {
        var brain = DemonBrain()
        _ = run(&brain, .rpm(4_000), seconds: 2)
        let frame = brain.update(input: .awaitingData, deltaTime: frameTime)
        #expect(frame.mood == .waitingForData)
        #expect(frame.smoothedRPM == nil)
        let resumed = brain.update(input: .rpm(800), deltaTime: frameTime)
        #expect(resumed.mood == .idle)
        #expect(resumed.smoothedRPM == 800)
    }

    @Test func customThresholdsAreRespected() {
        var thresholds = RPMThresholds.standard
        thresholds.awakeningStart = 1_500
        thresholds.awakeStart = 2_500
        thresholds.unleashedStart = 4_500
        var brain = DemonBrain(thresholds: thresholds)
        #expect(run(&brain, .rpm(1_300), seconds: 2).mood == .idle)
        #expect(run(&brain, .rpm(4_000), seconds: 2).mood == .awake)
    }

    @Test func largeFrameGapsAreClamped() {
        var brain = DemonBrain()
        _ = run(&brain, .rpm(800), seconds: 2)
        let frame = brain.update(input: .rpm(6_000), deltaTime: 30)
        // Ein einzelner riesiger Zeitsprung darf keinen Zustandswechsel erzwingen.
        #expect(frame.mood == .idle)
    }
}
