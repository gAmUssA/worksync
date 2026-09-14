import WorkSyncCore
import XCTest
@testable import worksync

/// Saving, both against a recorder and against the real `ConfigWriter` in a
/// temporary directory. A spy proves the model called the writer; only the real
/// writer proves the file a user would open afterwards.
@MainActor
final class SettingsSaveTests: XCTestCase {
    private func handle(_ model: MenuBarModel, _ id: String) throws -> SourceHandle {
        try XCTUnwrap(model.handle(of: id))
    }

    // MARK: What reaches the writer

    func testSavingPassesTheEditedConfigAndItsOrigins() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try handle(model, "personal")

        model.updateSource(personal) { $0.titleTemplate = "Unavailable" }
        model.saveSettings()

        let saved = try XCTUnwrap(recorder.savedConfigs.first)
        XCTAssertEqual(saved.config.sources[0].titleTemplate, "Unavailable")
        XCTAssertEqual(saved.origins, ["personal": "personal", "travel": "travel"])
        XCTAssertEqual(model.screen, .dashboard, "a good save closes the screen")
    }

    func testARenamedSourceTellsTheWriterWhereItCameFrom() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try handle(model, "personal")

        // Answering the purge warning is part of renaming a source the file
        // holds; `saveSettings` refuses while one is unanswered.
        MenuBarFixture.rename(model, personal, to: "home")
        model.saveSettings()

        let saved = try XCTUnwrap(recorder.savedConfigs.first)
        XCTAssertEqual(
            saved.origins["home"], "personal",
            "the writer needs the id on disk to find the block to edit"
        )
    }

    func testATypedDraftIsCommittedByTheSaveThatLooksLikeItIncludedIt() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try handle(model, "personal")

        model.setTitleFilterDraft(.matches, to: "standup", of: personal)
        model.saveSettings()

        let saved = try XCTUnwrap(recorder.savedConfigs.first)
        XCTAssertEqual(saved.config.sources[0].titleMatches, ["1:1", "standup"])
    }

    func testEntriesAreTrimmedOnTheWayToDisk() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        let personal = try handle(model, "personal")
        let row = try XCTUnwrap(model.titleFilterRows(.matches, of: personal).first)

        // A padded entry passes validation and then never matches anything.
        model.setTitleFilterEntry("  lunch  ", .matches, of: personal, row: row.id)
        model.saveSettings()

        let saved = try XCTUnwrap(recorder.savedConfigs.first)
        XCTAssertEqual(saved.config.sources[0].titleMatches, ["lunch"])
    }

    func testAFailedWriteLeavesTheFormOpenWithTheReason() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.saveError = ConfigWriteError.writeFailed("permission denied")

        model.saveSettings()

        XCTAssertEqual(model.screen, .settings, "nothing is closed over an error")
        XCTAssertNotNil(model.saveError)
        XCTAssertNotNil(model.editingConfig, "the user's edits are still there to retry")
    }

    func testAReserializedSaveWarnsAboutTheCommentsItLost() async throws {
        let (model, recorder, _) = try await MenuBarFixture.opened(config: MenuBarFixture.twoSources())
        recorder.saveOutcome = .reserialized

        model.saveSettings()

        XCTAssertNotNil(model.saveWarning, "comment loss is surfaced, not inferred later")
        XCTAssertEqual(model.screen, .dashboard)
    }

    // MARK: The real writer, on a real file

    func testEditingThroughTheModelPreservesTheFilesComments() async throws {
        let directory = NSTemporaryDirectory() + "x7nc-save-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let original = """
        # Hand-written, and it stays that way.
        [target]
        account = "Work"
        calendar = "Calendar"

        [[source]]
        # The personal calendar.
        id = "personal"
        account = "iCloud"
        calendar = "Personal"
        title_matches = [
          "1:1",
        ]

        [[source]]
        # The travel calendar.
        id = "travel"
        account = "Google"
        calendar = "Travel"
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        // The real config path, the real writer — only the system services are
        // fake, and this test uses none of them.
        let recorder = MenuBarRecorder()
        var services = MenuBarFixture.services(recorder: recorder)
        services.loadConfig = { try ConfigLoader.load(path: path) }
        services.saveConfig = { config, origins in
            try ConfigWriter.save(config, to: path, sourceOrigins: origins)
        }
        let model = MenuBarModel(
            initialState: MenuBarInitialState(
                isPaused: false, lastRun: nil, savedSourceIDs: ["personal", "travel"]
            ),
            services: services
        )

        model.openSettings()
        await model.calendarChoicesTask?.value
        let personal = try handle(model, "personal")
        model.setTitleFilterDraft(.matches, to: "interview", of: personal)
        model.addTitleFilter(.matches, to: personal)
        model.saveSettings()

        let written = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(written.contains("# Hand-written, and it stays that way."), written)
        XCTAssertTrue(written.contains("# The personal calendar."), written)
        XCTAssertTrue(written.contains("# The travel calendar."), written)

        let reloaded = try ConfigLoader.load(path: path)
        XCTAssertEqual(reloaded.sources[0].titleMatches, ["1:1", "interview"])
        XCTAssertEqual(reloaded.sources.map(\.id), ["personal", "travel"])
        XCTAssertNil(model.saveWarning, "the line edit held, so there is nothing to warn about")
    }

    func testRenamingThroughTheModelKeepsTheBlockItRenames() async throws {
        let directory = NSTemporaryDirectory() + "x7nc-rename-\(UUID().uuidString)"
        let path = directory + "/config.toml"
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let original = """
        [target]
        account = "Work"
        calendar = "Calendar"

        [[source]]
        # Personal block documentation.
        id = "personal"
        account = "iCloud"
        calendar = "Personal"

        [[source]]
        # Travel block documentation.
        id = "travel"
        account = "Google"
        calendar = "Travel"
        """
        try original.write(toFile: path, atomically: true, encoding: .utf8)

        let recorder = MenuBarRecorder()
        var services = MenuBarFixture.services(recorder: recorder)
        services.loadConfig = { try ConfigLoader.load(path: path) }
        services.saveConfig = { config, origins in
            try ConfigWriter.save(config, to: path, sourceOrigins: origins)
        }
        let model = MenuBarModel(
            initialState: MenuBarInitialState(isPaused: false, lastRun: nil, savedSourceIDs: []),
            services: services
        )

        model.openSettings()
        await model.calendarChoicesTask?.value
        let personal = try handle(model, "personal")
        MenuBarFixture.rename(model, personal, to: "home")
        model.saveSettings()

        let written = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertTrue(written.contains("id = \"home\""), written)
        XCTAssertTrue(
            written.contains("# Personal block documentation."),
            "the renamed source keeps its own documentation: \n\(written)"
        )
        XCTAssertTrue(written.contains("# Travel block documentation."), written)
    }
}
