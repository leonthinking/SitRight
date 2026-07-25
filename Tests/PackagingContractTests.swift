import Foundation
import XCTest
@testable import SitRight

final class PackagingContractTests: XCTestCase {
    func testAppAndWidgetEntitlementsUseTheSameAppGroupAsSharedStorage() throws {
        let appEntitlements = try plist(at: "AppBundle/SitRight.entitlements")
        let widgetEntitlements = try plist(at: "WidgetBundle/SitRightWidgetExtension.entitlements")

        let appGroups = try XCTUnwrap(
            appEntitlements["com.apple.security.application-groups"] as? [String]
        )
        let widgetGroups = try XCTUnwrap(
            widgetEntitlements["com.apple.security.application-groups"] as? [String]
        )

        XCTAssertEqual(appGroups, SharedStorage.appGroupIdentifiers)
        XCTAssertEqual(widgetGroups, SharedStorage.appGroupIdentifiers)
        XCTAssertEqual(appGroups, widgetGroups)
        XCTAssertEqual(appEntitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(widgetEntitlements["com.apple.security.app-sandbox"] as? Bool, true)
    }

    func testInfoPlistsPreserveMenuBarAppAndWidgetExtensionContracts() throws {
        let appInfo = try plist(at: "AppBundle/Info.plist")
        let widgetInfo = try plist(at: "WidgetBundle/Info.plist")
        let extensionInfo = try XCTUnwrap(widgetInfo["NSExtension"] as? [String: Any])

        XCTAssertEqual(appInfo["CFBundleIdentifier"] as? String, "com.leon.SitRight")
        XCTAssertEqual(appInfo["LSUIElement"] as? Bool, true)
        XCTAssertEqual(widgetInfo["CFBundleIdentifier"] as? String, "com.leon.SitRight.SitRightWidgetExtension")
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    func testProjectAndBuildScriptKeepBundleAndAppGroupIdentifiersInSync() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )

        XCTAssertEqual(
            exactLineCount("PRODUCT_BUNDLE_IDENTIFIER: com.leon.SitRight", in: project),
            1
        )
        XCTAssertEqual(
            exactLineCount(
                "PRODUCT_BUNDLE_IDENTIFIER: com.leon.SitRight.SitRightWidgetExtension",
                in: project
            ),
            1
        )
        XCTAssertEqual(exactLineCount("CODE_SIGN_ENTITLEMENTS: AppBundle/SitRight.entitlements", in: project), 1)
        XCTAssertEqual(
            exactLineCount(
                "CODE_SIGN_ENTITLEMENTS: WidgetBundle/SitRightWidgetExtension.entitlements",
                in: project
            ),
            1
        )
        for appGroup in SharedStorage.appGroupIdentifiers {
            XCTAssertEqual(exactLineCount("APP_GROUP_IDENTIFIER=\"\(appGroup)\"", in: buildScript), 1)
        }
    }

    func testReleaseBuildExplicitlyDisablesCoverageAndValidatesMachOBinaries() throws {
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )

        XCTAssertEqual(exactLineCount("ENABLE_CODE_COVERAGE: NO", in: project), 1)
        XCTAssertEqual(exactLineCount("CLANG_COVERAGE_MAPPING: NO", in: project), 1)
        XCTAssertEqual(exactLineCount("ENABLE_CODE_COVERAGE=NO \\", in: buildScript), 1)
        XCTAssertEqual(exactLineCount("CLANG_COVERAGE_MAPPING=NO \\", in: buildScript), 1)
        XCTAssertTrue(buildScript.contains("verify_release_executable"))
        XCTAssertTrue(buildScript.contains("__llvm_cov|__llvm_prf|__LLVM_COV"))
        XCTAssertTrue(buildScript.contains("/usr/bin/lipo -archs"))
    }

    func testBuildScriptSerializesFullFlowAndUsesUniqueTemporaryDirectories() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(buildScript.contains("exec /usr/bin/lockf"))
        XCTAssertTrue(buildScript.contains("SitRightDerivedData.XXXXXX"))
        XCTAssertTrue(buildScript.contains("Signed.XXXXXX"))
        XCTAssertTrue(buildScript.contains(".SitRightBuildOutput.XXXXXX"))
        XCTAssertTrue(buildScript.contains("trap cleanup EXIT"))
        XCTAssertTrue(buildScript.contains("trap 'exit 130' INT"))
        XCTAssertTrue(buildScript.contains("publish_built_app \"$STAGED_APP_PATH\" \"$APP_PATH\""))
        XCTAssertFalse(buildScript.contains("rm -rf \"$APP_PATH\""))
        XCTAssertTrue(buildScript.contains("SITRIGHT_KEEP_DERIVED_DATA"))
    }

    func testInstallValidatesStagesRegistersAndCanRollBack() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(buildScript.contains("EXPECTED_TEAM_IDENTIFIER=\"${APP_GROUP_IDENTIFIER%%.*}\""))
        XCTAssertTrue(buildScript.contains("/usr/bin/codesign -d --entitlements :- \"$target\""))
        XCTAssertTrue(
            buildScript.contains(
                "-extract \"com\\\\.apple\\\\.security\\\\.application-groups.$group_index\""
            )
        )
        XCTAssertTrue(buildScript.contains("[ \"$group_value\" = \"$APP_GROUP_IDENTIFIER\" ]"))
        XCTAssertTrue(buildScript.contains("com\\\\.apple\\\\.security\\\\.get-task-allow"))
        XCTAssertTrue(buildScript.contains("verify_installable_app \"$source_app\" \"Source\""))
        XCTAssertTrue(buildScript.contains("prepare_install_candidate \"$source_app\" \"$candidate_app\""))
        XCTAssertTrue(buildScript.contains("mv \"$install_app\" \"$previous_app\""))
        XCTAssertTrue(buildScript.contains("mv \"$candidate_app\" \"$install_app\""))
        XCTAssertTrue(buildScript.contains("rollback_installation_transaction"))
        XCTAssertTrue(buildScript.contains("recover_interrupted_installation"))
        XCTAssertTrue(buildScript.contains(".SitRightInstallTransaction"))
        XCTAssertTrue(buildScript.contains("write_install_transaction_state \"committed\""))
        XCTAssertTrue(buildScript.contains("/usr/bin/pluginkit -a \"$install_widget\""))
        XCTAssertTrue(buildScript.contains("register_installed_app \"$install_app\""))
        XCTAssertTrue(buildScript.contains("Widget registration did not resolve uniquely"))
        XCTAssertTrue(buildScript.contains("registered_path_count\" = \"1\""))
        XCTAssertTrue(buildScript.contains("expected_path_count\" = \"1\""))

        let installFunction = try function(named: "install_to_applications", in: buildScript)
        let sourceValidation = try XCTUnwrap(
            installFunction.range(of: "verify_installable_app \"$source_app\" \"Source\"")
        )
        let recovery = try XCTUnwrap(
            installFunction.range(of: "recover_interrupted_installation")
        )
        let candidatePreparation = try XCTUnwrap(
            installFunction.range(of: "prepare_install_candidate \"$source_app\" \"$candidate_app\"")
        )
        let replacementState = try XCTUnwrap(
            installFunction.range(of: "write_install_transaction_state \"replacing\"")
        )
        let processStop = try XCTUnwrap(installFunction.range(of: "/usr/bin/pkill -x SitRight"))
        let replacement = try XCTUnwrap(
            installFunction.range(of: "mv \"$install_app\" \"$previous_app\"")
        )
        let installedState = try XCTUnwrap(
            installFunction.range(of: "write_install_transaction_state \"installed\"")
        )
        let installedValidation = try XCTUnwrap(
            installFunction.range(of: "verify_installable_app \"$install_app\" \"Installed\"")
        )
        let registration = try XCTUnwrap(
            installFunction.range(of: "register_installed_app \"$install_app\"")
        )

        XCTAssertLessThan(sourceValidation.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(recovery.lowerBound, candidatePreparation.lowerBound)
        XCTAssertLessThan(candidatePreparation.lowerBound, replacementState.lowerBound)
        XCTAssertLessThan(replacementState.lowerBound, processStop.lowerBound)
        XCTAssertLessThan(processStop.lowerBound, replacement.lowerBound)
        XCTAssertLessThan(replacement.lowerBound, installedState.lowerBound)
        XCTAssertLessThan(installedState.lowerBound, installedValidation.lowerBound)
        XCTAssertLessThan(installedValidation.lowerBound, registration.lowerBound)

        let rollbackFunction = try function(named: "rollback_installation_transaction", in: buildScript)
        XCTAssertTrue(rollbackFunction.contains("register_installed_app \"$INSTALL_APP_PATH\" || return 1"))
        XCTAssertFalse(buildScript.contains("rm -rf \"$install_app\""))
    }

    func testDMGPackagingBuildsAndRejectsBrokenAppGroupArtifactsBeforeCreatingImage() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/package_dmg.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(packageScript.contains("exec /usr/bin/lockf"))
        XCTAssertTrue(packageScript.contains("export SITRIGHT_BUILD_LOCK_HELD=1"))
        XCTAssertTrue(packageScript.contains("SITRIGHT_OUTPUT_APP_PATH=\"$built_app_path\""))
        XCTAssertTrue(packageScript.contains("SITRIGHT_INSTALL_TO_APPLICATIONS=0"))
        XCTAssertTrue(packageScript.contains("EXPECTED_TEAM_IDENTIFIER=\"${APP_GROUP_IDENTIFIER%%.*}\""))
        XCTAssertTrue(packageScript.contains("verify_app_group_contract \"$app_path\""))
        XCTAssertTrue(packageScript.contains("verify_app_group_contract \"$widget_path\""))
        XCTAssertTrue(packageScript.contains("/usr/bin/codesign -d --entitlements :- \"$target\""))
        XCTAssertTrue(
            packageScript.contains(
                "-extract \"com\\\\.apple\\\\.security\\\\.application-groups.$group_index\""
            )
        )
        XCTAssertTrue(packageScript.contains("[ \"$group_value\" = \"$APP_GROUP_IDENTIFIER\" ]"))
        XCTAssertTrue(packageScript.contains("com\\\\.apple\\\\.security\\\\.get-task-allow"))
        XCTAssertTrue(packageScript.contains("/usr/bin/codesign --verify --strict \"$widget_path\""))
        XCTAssertTrue(packageScript.contains("/usr/bin/codesign --verify --strict --deep \"$app_path\""))
        XCTAssertTrue(packageScript.contains("App and Widget architectures differ"))
        XCTAssertTrue(packageScript.contains("-format UDZO"))
        XCTAssertTrue(packageScript.contains("-fs HFS+"))
        XCTAssertFalse(packageScript.contains("-ov"))
        XCTAssertTrue(packageScript.contains("/usr/bin/hdiutil verify \"$candidate_dmg_path\""))
        XCTAssertTrue(packageScript.contains("/usr/bin/hdiutil attach"))
        XCTAssertTrue(
            packageScript.contains(
                "/usr/bin/diff -qr \"$STAGED_APP_PATH\" \"$MOUNT_POINT/SitRight.app\""
            )
        )
        XCTAssertTrue(packageScript.contains("mounted DMG is missing Applications -> /Applications"))
        XCTAssertTrue(packageScript.contains("publish_artifact_pair"))
        XCTAssertTrue(packageScript.contains("rollback_artifact_transaction"))
        XCTAssertTrue(packageScript.contains("recover_interrupted_publication"))
        XCTAssertTrue(packageScript.contains("write_transaction_state \"committed\""))
        XCTAssertTrue(packageScript.contains("trap 'exit 130' INT"))
        XCTAssertTrue(packageScript.contains("previous.dmg.sha256"))
        XCTAssertTrue(packageScript.contains("OPEN_DMG_ON_SUCCESS"))

        let build = try XCTUnwrap(
            packageScript.range(of: "SITRIGHT_OUTPUT_APP_PATH=\"$built_app_path\"")
        )
        let builtValidation = try XCTUnwrap(
            packageScript.range(of: "verify_packageable_app \"$built_app_path\" \"Built\"")
        )
        let imageCreation = try XCTUnwrap(
            packageScript.range(of: "/usr/bin/hdiutil create")
        )
        let imageVerification = try XCTUnwrap(
            packageScript.range(of: "/usr/bin/hdiutil verify \"$candidate_dmg_path\"")
        )
        let imageMount = try XCTUnwrap(
            packageScript.range(of: "/usr/bin/hdiutil attach")
        )
        let contentComparison = try XCTUnwrap(
            packageScript.range(
                of: "/usr/bin/diff -qr \"$STAGED_APP_PATH\" \"$MOUNT_POINT/SitRight.app\""
            )
        )
        let checksum = try XCTUnwrap(
            packageScript.range(of: "sha256=\"$(/usr/bin/shasum -a 256 \"$candidate_dmg_path\"")
        )
        let publication = try XCTUnwrap(
            packageScript.range(
                of: """
                publish_artifact_pair \\
                    "$candidate_dmg_path" \\
                    "$candidate_checksum_path" \\
                    "$dmg_path" \\
                    "$checksum_path"
                """
            )
        )

        XCTAssertLessThan(build.lowerBound, builtValidation.lowerBound)
        XCTAssertLessThan(builtValidation.lowerBound, imageCreation.lowerBound)
        XCTAssertLessThan(imageCreation.lowerBound, imageVerification.lowerBound)
        XCTAssertLessThan(imageVerification.lowerBound, imageMount.lowerBound)
        XCTAssertLessThan(imageMount.lowerBound, contentComparison.lowerBound)
        XCTAssertLessThan(contentComparison.lowerBound, checksum.lowerBound)
        XCTAssertLessThan(checksum.lowerBound, publication.lowerBound)
    }

    func testBuildAndDMGEntitlementValidationRejectCrossFieldMatchesAndDebugging() throws {
        let expectedGroup = try XCTUnwrap(SharedStorage.appGroupIdentifiers.first)
        let validEntitlements: [String: Any] = [
            "com.apple.security.application-groups": [expectedGroup],
            "com.apple.security.get-task-allow": false
        ]
        let misleadingEntitlements: [String: Any] = [
            "com.apple.security.application-groups": ["WRONGTEAM.com.leon.SitRight"],
            "keychain-access-groups": [expectedGroup],
            "com.apple.security.get-task-allow": false
        ]
        let debuggingEntitlements: [String: Any] = [
            "com.apple.security.application-groups": [expectedGroup],
            "com.apple.security.get-task-allow": true
        ]

        for scriptPath in ["Scripts/build_app.sh", "Scripts/package_dmg.sh"] {
            XCTAssertEqual(
                try entitlementValidationExitStatus(
                    for: validEntitlements,
                    scriptPath: scriptPath
                ),
                0,
                scriptPath
            )
            XCTAssertNotEqual(
                try entitlementValidationExitStatus(
                    for: misleadingEntitlements,
                    scriptPath: scriptPath
                ),
                0,
                scriptPath
            )
            XCTAssertNotEqual(
                try entitlementValidationExitStatus(
                    for: debuggingEntitlements,
                    scriptPath: scriptPath
                ),
                0,
                scriptPath
            )
        }
    }

    func testInterruptedDMGPublicationRestoresPreviousArtifactPair() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/package_dmg.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightDMGRecovery-\(UUID().uuidString)", isDirectory: true)
        let transactionDirectory = temporaryDirectory.appendingPathComponent(".SitRightDMGTransaction")
        let finalDMG = temporaryDirectory.appendingPathComponent("SitRight-test.dmg")
        let finalChecksum = temporaryDirectory.appendingPathComponent("SitRight-test.dmg.sha256")
        try FileManager.default.createDirectory(
            at: transactionDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try Data("new-dmg".utf8).write(to: finalDMG)
        try Data("old-dmg".utf8).write(
            to: transactionDirectory.appendingPathComponent("previous.dmg")
        )
        try Data("old-checksum".utf8).write(
            to: transactionDirectory.appendingPathComponent("previous.dmg.sha256")
        )
        try Data("SitRight-test.dmg\n".utf8).write(
            to: transactionDirectory.appendingPathComponent("final-dmg-name")
        )
        try Data("SitRight-test.dmg.sha256\n".utf8).write(
            to: transactionDirectory.appendingPathComponent("final-checksum-name")
        )
        try Data().write(to: transactionDirectory.appendingPathComponent("had-previous-dmg"))
        try Data().write(to: transactionDirectory.appendingPathComponent("had-previous-checksum"))
        try Data("dmg-published\n".utf8).write(
            to: transactionDirectory.appendingPathComponent("state")
        )

        let runner = """
        set -euo pipefail
        OUTPUT_DIR="$1"
        OUTPUT_TRANSACTION_DIR="$OUTPUT_DIR/.SitRightDMGTransaction"
        OUTPUT_STAGING_DIR="$OUTPUT_TRANSACTION_DIR"
        \(try function(named: "write_transaction_state", in: packageScript))
        \(try function(named: "transaction_output_name", in: packageScript))
        \(try function(named: "rollback_artifact_transaction", in: packageScript))
        rollback_artifact_transaction
        """
        XCTAssertEqual(
            try bashExitStatus(script: runner, arguments: [temporaryDirectory.path]),
            0
        )
        XCTAssertEqual(try String(contentsOf: finalDMG, encoding: .utf8), "old-dmg")
        XCTAssertEqual(try String(contentsOf: finalChecksum, encoding: .utf8), "old-checksum")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transactionDirectory.path))
    }

    func testInterruptedApplicationInstallRestoresAndRegistersPreviousApp() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightInstallRecovery-\(UUID().uuidString)", isDirectory: true)
        let installApp = temporaryDirectory.appendingPathComponent("SitRight.app", isDirectory: true)
        let transactionDirectory = temporaryDirectory
            .appendingPathComponent(".SitRightInstallTransaction", isDirectory: true)
        let previousApp = transactionDirectory
            .appendingPathComponent("PreviousSitRight.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installApp,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: previousApp,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try Data("new-app".utf8).write(to: installApp.appendingPathComponent("marker"))
        try Data("old-app".utf8).write(to: previousApp.appendingPathComponent("marker"))
        try Data().write(to: transactionDirectory.appendingPathComponent("had-previous-app"))
        try Data("installed\n".utf8).write(
            to: transactionDirectory.appendingPathComponent("state")
        )

        let runner = """
        set -euo pipefail
        INSTALL_APP_PATH="$1/SitRight.app"
        INSTALL_TRANSACTION_DIR="$1/.SitRightInstallTransaction"
        INSTALL_TRANSACTION_ACTIVE=1
        unregister_transient_app() { :; }
        register_installed_app() { :; }
        \(try function(named: "write_install_transaction_state", in: buildScript))
        \(try function(named: "rollback_installation_transaction", in: buildScript))
        rollback_installation_transaction
        """
        XCTAssertEqual(
            try bashExitStatus(script: runner, arguments: [temporaryDirectory.path]),
            0
        )
        XCTAssertEqual(
            try String(
                contentsOf: installApp.appendingPathComponent("marker"),
                encoding: .utf8
            ),
            "old-app"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: transactionDirectory.path))
    }

    private func plist(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func exactLineCount(_ expectedLine: String, in text: String) -> Int {
        text.split(whereSeparator: \.isNewline).count { line in
            line.trimmingCharacters(in: .whitespaces) == expectedLine
        }
    }

    private func function(named name: String, in script: String) throws -> Substring {
        let start = try XCTUnwrap(script.range(of: "\(name)() {"))
        let remaining = script[start.lowerBound...]
        let end = try XCTUnwrap(remaining.range(of: "\n}\n", range: start.upperBound..<remaining.endIndex))
        return script[start.lowerBound..<end.upperBound]
    }

    private func entitlementValidationExitStatus(
        for entitlements: [String: Any],
        scriptPath: String
    ) throws -> Int32 {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightPackagingContract-\(UUID().uuidString)", isDirectory: true)
        let entitlementsURL = temporaryDirectory.appendingPathComponent("entitlements.plist")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: entitlements,
            format: .xml,
            options: 0
        )
        try data.write(to: entitlementsURL)

        let script = try String(
            contentsOf: repositoryRoot.appendingPathComponent(scriptPath),
            encoding: .utf8
        )
        let runner = """
        set -euo pipefail
        APP_GROUP_IDENTIFIER="\(try XCTUnwrap(SharedStorage.appGroupIdentifiers.first))"
        \(try function(named: "validate_entitlements_xml", in: script))
        validate_entitlements_xml "$(/bin/cat "$1")" "Fixture"
        """
        return try bashExitStatus(script: runner, arguments: [entitlementsURL.path])
    }

    private func bashExitStatus(script: String, arguments: [String]) throws -> Int32 {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightBashContract-\(UUID().uuidString)", isDirectory: true)
        let runnerURL = temporaryDirectory.appendingPathComponent("runner.sh")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try script.write(to: runnerURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [runnerURL.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
