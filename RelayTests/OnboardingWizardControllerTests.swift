import XCTest
@testable import Relay

final class OnboardingWizardControllerTests: XCTestCase {

    func test_start_pro_presentsFullStepSequence() {
        let controller = OnboardingWizardController()

        controller.start(hasPro: true)

        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.step, .welcome)
        XCTAssertEqual(controller.activeSteps, [.welcome, .connections, .devices, .audioInputs, .starterTiles, .reviewAndCreate])
    }

    func test_start_free_presentsPCOConnectionStepBeforeStarterTiles() {
        let controller = OnboardingWizardController()

        controller.start(hasPro: false)

        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(controller.step, .welcome)
        XCTAssertEqual(controller.activeSteps, [.welcome, .connections, .starterTiles, .reviewAndCreate])
    }

    func test_start_resetsStarterTileSelectionsFromPreviousRun() {
        let controller = OnboardingWizardController()
        controller.start(hasPro: true)
        controller.starterTileSelections = [
            OnboardingTileCandidate(
                id: UUID(),
                title: "Text",
                module: DashboardModuleModel(kind: .text(TextModuleModel(header: nil, content: AttributedString("hi"))), order: 0)
            )
        ]

        controller.start(hasPro: true)

        XCTAssertTrue(controller.starterTileSelections.isEmpty)
    }

    func test_next_pro_advancesThroughEveryStepInOrder() {
        let controller = OnboardingWizardController()
        controller.start(hasPro: true)

        let expectedOrder: [OnboardingStep] = [.connections, .devices, .audioInputs, .starterTiles, .reviewAndCreate]
        for expected in expectedOrder {
            controller.next()
            XCTAssertEqual(controller.step, expected)
        }
    }

    func test_next_free_advancesThroughEveryStepInOrder() {
        let controller = OnboardingWizardController()
        controller.start(hasPro: false)

        let expectedOrder: [OnboardingStep] = [.connections, .starterTiles, .reviewAndCreate]
        for expected in expectedOrder {
            controller.next()
            XCTAssertEqual(controller.step, expected)
        }
    }

    func test_next_pastFinalStep_dismissesWizard() {
        let controller = OnboardingWizardController()
        controller.start(hasPro: false)
        for _ in controller.activeSteps.dropFirst() {
            controller.next()
        }
        XCTAssertEqual(controller.step, .reviewAndCreate)
        XCTAssertTrue(controller.isPresented)

        controller.next()

        XCTAssertFalse(controller.isPresented)
    }

    func test_back_returnsToPreviousStep_andStaysAtWelcome() {
        let controller = OnboardingWizardController()
        controller.start(hasPro: true)
        controller.next() // .connections

        controller.back()
        XCTAssertEqual(controller.step, .welcome)

        controller.back()
        XCTAssertEqual(controller.step, .welcome)
    }

    func test_skip_behavesLikeNext() {
        let controller = OnboardingWizardController()
        controller.start(hasPro: true)

        controller.skip()

        XCTAssertEqual(controller.step, .connections)
    }
}
