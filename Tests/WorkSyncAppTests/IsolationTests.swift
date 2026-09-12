import Foundation
import WorkSyncCore
import XCTest
@testable import worksync

/// The suite must be safe to run on a fresh machine and in CI: no calendar
/// prompt, nothing written to the user's config, log or defaults. Asserted
/// rather than assumed, because "the fakes cover everything" is exactly the kind
/// of claim that quietly stops being true.
@MainActor
final class IsolationTests: XCTestCase {
    func testTheUsersConfigIsNeverTouchedByTheSuite() throws {
        let userConfig = ConfigLoader.defaultPath
        let before = modificationDate(of: userConfig)

        // Everything a settings session does, against fakes.
        let (model, _, _) = try MenuBarFixture.model(config: MenuBarFixture.twoSources())
        model.openSettings()
        if let handle = model.selectedSource {
            model.setTitleFilterDraft(.matches, to: "standup", of: handle)
            model.addTitleFilter(.matches, to: handle)
        }
        model.saveSettings()

        XCTAssertEqual(
            modificationDate(of: userConfig), before,
            "a test wrote to \(userConfig)"
        )
    }

    func testTheModelHasNoDefaultPathToTheRealWorld() {
        // There is no initializer that reaches live services, so there is no way
        // to construct one by accident: the live composition is a named factory
        // that production calls and tests do not.
        let model = MenuBarModel(
            initialState: MenuBarInitialState(isPaused: false, lastRun: nil, savedSourceIDs: []),
            services: MenuBarFixture.failOnCall()
        )
        XCTAssertEqual(model.screen, .dashboard)
    }

    /// The one place live services may appear. A grep is a blunt instrument, but
    /// this is the property that keeps the suite safe, and it is cheap to check.
    func testEffectfulTypesAppearOnlyInTheLiveServicesFile() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // WorkSyncAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Sources/worksync/MenuBar")

        let live = ["LiveMenuBarServices.swift", "UserNotifier.swift", "StatusItemController.swift"]
        let banned = ["EventKitStore(", "DoctorFacts.gather", "UserDefaults.standard", "PassRunner.run"]

        for file in try FileManager.default.contentsOfDirectory(atPath: root.path)
            where file.hasSuffix(".swift") && !live.contains(file) {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for token in banned {
                XCTAssertFalse(
                    text.contains(token),
                    "\(file) reaches the system directly (\(token)); route it through MenuBarServices"
                )
            }
        }
    }

    private func modificationDate(of path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
