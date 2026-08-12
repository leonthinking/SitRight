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
        XCTAssertEqual(
            Set(
                try XCTUnwrap(
                    appEntitlements[
                        "com.apple.security.temporary-exception.mach-lookup.global-name"
                    ] as? [String]
                )
            ),
            Set([
                "com.leon.SitRight-spki",
                "com.leon.SitRight-spks"
            ])
        )
        XCTAssertNil(
            widgetEntitlements[
                "com.apple.security.temporary-exception.mach-lookup.global-name"
            ]
        )
    }

    func testInfoPlistsPreserveMenuBarAppAndWidgetExtensionContracts() throws {
        let appInfo = try plist(at: "AppBundle/Info.plist")
        let widgetInfo = try plist(at: "WidgetBundle/Info.plist")
        let extensionInfo = try XCTUnwrap(widgetInfo["NSExtension"] as? [String: Any])

        XCTAssertEqual(appInfo["CFBundleIdentifier"] as? String, "com.leon.SitRight")
        XCTAssertEqual(appInfo["LSUIElement"] as? Bool, true)
        XCTAssertEqual(
            appInfo["SUFeedURL"] as? String,
            UpdateConfiguration.expectedFeedURL.absoluteString
        )
        XCTAssertEqual(appInfo["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(appInfo["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(appInfo["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertEqual(appInfo["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(appInfo["SUEnableDownloaderService"] as? Bool, true)
        XCTAssertEqual(
            appInfo["SUEnableInstallerLauncherService"] as? Bool,
            true
        )
        XCTAssertEqual(appInfo["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(
            appInfo["SUVerifyUpdateBeforeExtraction"] as? Bool,
            true
        )
        XCTAssertEqual(
            appInfo["SUSignedFeedFailureExpirationInterval"] as? Int,
            0
        )
        let publicKey = try XCTUnwrap(appInfo["SUPublicEDKey"] as? String)
        XCTAssertNotEqual(
            publicKey,
            UpdateConfiguration.publicKeyPlaceholder
        )
        XCTAssertEqual(Data(base64Encoded: publicKey)?.count, 32)
        XCTAssertEqual(widgetInfo["CFBundleIdentifier"] as? String, "com.leon.SitRight.SitRightWidgetExtension")
        XCTAssertEqual(extensionInfo["NSExtensionPointIdentifier"] as? String, "com.apple.widgetkit-extension")
    }

    func testSparkleDependencyIsPinnedExactlyAcrossBuildSystems() throws {
        let package = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let resolved = try plistJSON(
            at: repositoryRoot.appendingPathComponent("Package.resolved")
        )
        let pins = try XCTUnwrap(resolved["pins"] as? [[String: Any]])
        let sparklePin = try XCTUnwrap(
            pins.first { $0["identity"] as? String == "sparkle" }
        )
        let state = try XCTUnwrap(sparklePin["state"] as? [String: Any])

        XCTAssertTrue(
            package.contains(
                "url: \"https://github.com/sparkle-project/Sparkle\""
            )
        )
        XCTAssertTrue(package.contains("exact: \"2.9.2\""))
        XCTAssertTrue(project.contains("exactVersion: 2.9.2"))
        XCTAssertTrue(project.contains("- package: Sparkle"))
        XCTAssertEqual(state["version"] as? String, "2.9.2")
        XCTAssertEqual(
            sparklePin["location"] as? String,
            "https://github.com/sparkle-project/Sparkle"
        )
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
        XCTAssertTrue(buildScript.contains("sign_sparkle_components"))
        XCTAssertTrue(buildScript.contains("verify_sparkle_components"))
        let sparkleSigning = try function(
            named: "sign_sparkle_components",
            in: buildScript
        )
        XCTAssertTrue(sparkleSigning.contains("Downloader.xpc"))
        XCTAssertTrue(sparkleSigning.contains("Installer.xpc"))
        XCTAssertTrue(sparkleSigning.contains("Updater.app"))
        XCTAssertTrue(sparkleSigning.contains("Autoupdate"))
        XCTAssertTrue(sparkleSigning.contains("--options runtime"))
        XCTAssertTrue(
            sparkleSigning.contains(
                "--preserve-metadata=entitlements"
            )
        )
        XCTAssertFalse(sparkleSigning.contains("requirements"))
        XCTAssertFalse(sparkleSigning.contains("--deep"))
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
        XCTAssertTrue(buildScript.contains("\"$PLUGINKIT\" -a \"$install_widget\""))
        XCTAssertTrue(buildScript.contains("unregister_competing_widget_registrations \"$install_widget\""))
        XCTAssertTrue(buildScript.contains("\"$PLUGINKIT\" -m -A -D -v"))
        XCTAssertTrue(buildScript.contains("register_installed_app \"$install_app\""))
        XCTAssertTrue(buildScript.contains("terminate_running_widget_extension"))
        XCTAssertFalse(buildScript.contains("pkill -x SitRightWidgetExtension"))
        XCTAssertTrue(buildScript.contains("Widget registration did not resolve uniquely"))
        XCTAssertTrue(buildScript.contains("registered_path_count\" = \"1\""))
        XCTAssertTrue(buildScript.contains("expected_path_count\" = \"1\""))
        XCTAssertTrue(buildScript.contains("stable_registration_count\" = \"3\""))
        XCTAssertTrue(buildScript.contains("$target_parent/.metadata_never_index"))
        XCTAssertTrue(buildScript.contains("unregister_transient_app \"$APP_PATH\""))
        XCTAssertTrue(
            buildScript.contains(
                "SITRIGHT_OUTPUT_APP_PATH must differ from $INSTALL_APP_PATH when installation is enabled"
            )
        )
        XCTAssertTrue(buildScript.contains("normalize_absolute_path_lexically"))
        XCTAssertTrue(buildScript.contains("canonical_path_allowing_missing"))
        XCTAssertTrue(buildScript.contains("path_has_parent_traversal"))
        XCTAssertTrue(
            buildScript.contains(
                "SITRIGHT_OUTPUT_APP_PATH must not contain parent-directory traversal when installation is enabled"
            )
        )

        let outputPathGuard = try XCTUnwrap(
            buildScript.range(
                of: "SITRIGHT_OUTPUT_APP_PATH must differ from $INSTALL_APP_PATH when installation is enabled"
            )
        )
        let projectGeneration = try XCTUnwrap(buildScript.range(of: "xcodegen generate"))
        XCTAssertLessThan(outputPathGuard.lowerBound, projectGeneration.lowerBound)

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
        let oldRegistrationRemoval = try XCTUnwrap(
            installFunction.range(of: "unregister_transient_app \"$install_app\"")
        )
        let initialProcessStop = try XCTUnwrap(
            installFunction.range(of: "stop_running_sitright_processes")
        )
        let replacement = try XCTUnwrap(
            installFunction.range(of: "mv \"$install_app\" \"$previous_app\"")
        )
        let installedState = try XCTUnwrap(
            installFunction.range(of: "write_install_transaction_state \"installed\"")
        )
        let installedValidation = try XCTUnwrap(
            installFunction.range(of: "verify_installable_app \"$install_app\" \"Installed\"")
        )
        let finalSourceUnregistration = try XCTUnwrap(
            installFunction.range(
                of: "unregister_transient_app \"$source_app\"",
                options: .backwards
            )
        )
        let sourceIsolation = try XCTUnwrap(
            installFunction.range(of: "mv \"$source_app\" \"$isolated_source_app\"")
        )
        let registration = try XCTUnwrap(
            installFunction.range(of: "register_installed_app \"$install_app\"")
        )
        let finalWidgetProcessStop = try XCTUnwrap(
            installFunction.range(of: "terminate_running_widget_extension")
        )

        XCTAssertLessThan(sourceValidation.lowerBound, recovery.lowerBound)
        XCTAssertLessThan(recovery.lowerBound, candidatePreparation.lowerBound)
        XCTAssertLessThan(candidatePreparation.lowerBound, replacementState.lowerBound)
        XCTAssertLessThan(replacementState.lowerBound, oldRegistrationRemoval.lowerBound)
        XCTAssertLessThan(oldRegistrationRemoval.lowerBound, initialProcessStop.lowerBound)
        XCTAssertLessThan(initialProcessStop.lowerBound, replacement.lowerBound)
        XCTAssertLessThan(replacement.lowerBound, installedState.lowerBound)
        XCTAssertLessThan(installedState.lowerBound, installedValidation.lowerBound)
        XCTAssertLessThan(installedValidation.lowerBound, finalSourceUnregistration.lowerBound)
        XCTAssertLessThan(finalSourceUnregistration.lowerBound, sourceIsolation.lowerBound)
        XCTAssertLessThan(sourceIsolation.lowerBound, finalWidgetProcessStop.lowerBound)
        XCTAssertLessThan(finalWidgetProcessStop.lowerBound, registration.lowerBound)
        XCTAssertLessThan(sourceIsolation.lowerBound, registration.lowerBound)
        XCTAssertLessThan(installedValidation.lowerBound, registration.lowerBound)
        XCTAssertEqual(
            exactLineCount("unregister_transient_app \"$source_app\"", in: String(installFunction)),
            2
        )
        XCTAssertEqual(
            exactLineCount("if ! stop_running_sitright_processes; then", in: String(installFunction)),
            1
        )
        XCTAssertEqual(
            exactLineCount("if ! terminate_running_widget_extension; then", in: String(installFunction)),
            1
        )

        let rollbackFunction = try function(named: "rollback_installation_transaction", in: buildScript)
        XCTAssertTrue(rollbackFunction.contains("register_installed_app \"$INSTALL_APP_PATH\" || return 1"))
        XCTAssertTrue(rollbackFunction.contains("if ! stop_running_sitright_processes; then"))
        let rollbackStop = try XCTUnwrap(
            rollbackFunction.range(of: "stop_running_sitright_processes")
        )
        let rollbackReplacement = try XCTUnwrap(
            rollbackFunction.range(of: "rm -rf \"$INSTALL_APP_PATH\"")
        )
        XCTAssertLessThan(rollbackStop.lowerBound, rollbackReplacement.lowerBound)
        XCTAssertFalse(buildScript.contains("rm -rf \"$install_app\""))
        XCTAssertFalse(buildScript.contains("/usr/bin/pkill"))
    }

    func testWidgetTerminationIsAbsentSafeAndRejectsProcessesThatRemainActive() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightWidgetStop-\(UUID().uuidString)", isDirectory: true)
        let fakeKillall = temporaryDirectory.appendingPathComponent("killall")
        let stateFile = temporaryDirectory.appendingPathComponent("state")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let fakeKillallScript = """
        #!/bin/bash
        set -eu
        mode="${FAKE_KILLALL_MODE:?}"
        state_file="${FAKE_KILLALL_STATE:?}"
        query_file="${state_file}.queries"

        if [[ " $* " == *" -s "* ]]; then
          query_count=0
          [ ! -f "$query_file" ] || query_count="$(cat "$query_file")"
          query_count=$((query_count + 1))
          printf '%s\n' "$query_count" >"$query_file"
          case "$mode" in
            absent)
              exit 1
              ;;
            probe-error)
              exit 2
              ;;
            delayed-success)
              if [ "$query_count" -ge 7 ]; then
                printf 'stopped\n' >"$state_file"
              fi
              ;;
          esac
          [ "$(cat "$state_file")" = "running" ]
          exit $?
        fi

        if [[ " $* " == *" -TERM "* ]]; then
          case "$mode" in
            success)
              printf 'stopped\n' >"$state_file"
              exit 0
              ;;
            stubborn | delayed-success)
              exit 0
              ;;
            term-failure)
              exit 1
              ;;
          esac
        fi
        exit 2
        """
        try Data(fakeKillallScript.utf8).write(to: fakeKillall)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeKillall.path
        )

        let runner = """
        set -euo pipefail
        KILLALL="$1"
        WIDGET_PROCESS_NAME="SitRightWidgetExtension"
        SITRIGHT_PROCESS_STOP_POLL_INTERVAL=0
        export FAKE_KILLALL_MODE="$2"
        export FAKE_KILLALL_STATE="$3"
        \(try function(named: "terminate_running_named_process", in: buildScript))
        \(try function(named: "terminate_running_widget_extension", in: buildScript))
        terminate_running_widget_extension
        """

        for (mode, expectedStatus) in [
            ("absent", Int32(0)),
            ("success", Int32(0)),
            ("delayed-success", Int32(0)),
            ("stubborn", Int32(1)),
            ("term-failure", Int32(1)),
            ("probe-error", Int32(1))
        ] {
            try Data("running\n".utf8).write(to: stateFile)
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: stateFile.path + ".queries")
            )
            XCTAssertEqual(
                try bashExitStatus(
                    script: runner,
                    arguments: [fakeKillall.path, mode, stateFile.path]
                ),
                expectedStatus,
                "Unexpected Widget termination result for mode \(mode)"
            )
        }
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
                "write_tree_manifest \"$STAGED_APP_PATH\" \"$staged_manifest\""
            )
        )
        XCTAssertTrue(
            packageScript.contains(
                "write_tree_manifest \"$MOUNT_POINT/SitRight.app\" \"$mounted_manifest\""
            )
        )
        XCTAssertTrue(
            packageScript.contains(
                "/usr/bin/diff -u \"$staged_manifest\" \"$mounted_manifest\""
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
        XCTAssertTrue(
            packageScript.contains(
                "built_app_path=\"$STAGING_DIR/build/BuiltSitRight.app\""
            )
        )
        XCTAssertTrue(
            packageScript.contains(
                "image_staging_dir=\"$STAGING_DIR/image\""
            )
        )
        XCTAssertTrue(
            packageScript.contains("-srcfolder \"$image_staging_dir\"")
        )
        XCTAssertFalse(
            packageScript.contains("-srcfolder \"$STAGING_DIR\"")
        )
        XCTAssertTrue(
            packageScript.contains(
                "mounted DMG must contain only SitRight.app and Applications"
            )
        )
        XCTAssertTrue(packageScript.contains("verify_sparkle_components"))
        XCTAssertTrue(packageScript.contains("SITRIGHT_DMG_RESULT_PATH"))

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
                of: "/usr/bin/diff -u \"$staged_manifest\" \"$mounted_manifest\""
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

    func testCommunityUpdateScriptsEnforceSignedCompleteAtomicRelease() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/package_update.sh"
            ),
            encoding: .utf8
        )
        let publishScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/publish_update_release.sh"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            packageScript.contains(
                "SPARKLE_KEY_ACCOUNT=\"${SITRIGHT_SPARKLE_KEY_ACCOUNT:-com.leon.SitRight}\""
            )
        )
        XCTAssertTrue(packageScript.contains("generate_appcast"))
        XCTAssertTrue(packageScript.contains("generate_keys"))
        XCTAssertTrue(packageScript.contains("sign_update"))
        XCTAssertTrue(packageScript.contains("--verify"))
        XCTAssertTrue(packageScript.contains("--maximum-deltas 0"))
        XCTAssertTrue(packageScript.contains("SITRIGHT_RELEASE_TAG"))
        XCTAssertTrue(packageScript.contains("SITRIGHT_RELEASE_NOTES_FILE"))
        XCTAssertTrue(packageScript.contains("--embed-release-notes"))
        XCTAssertTrue(packageScript.contains("embedded_release_notes_count"))
        XCTAssertTrue(packageScript.contains("external_release_notes_count"))
        XCTAssertTrue(packageScript.contains("release tag $tag must match app version"))
        XCTAssertTrue(packageScript.contains("the embedded Sparkle public key does not match"))
        XCTAssertTrue(packageScript.contains("update ZIP must contain only the SitRight.app hierarchy"))
        XCTAssertTrue(packageScript.contains("verify_update_zip_contents"))
        XCTAssertTrue(packageScript.contains("--norsrc"))
        XCTAssertFalse(packageScript.contains("--sequesterRsrc"))
        XCTAssertTrue(packageScript.contains("appcast_source_dir=\"$WORK_DIR/appcast-source\""))
        XCTAssertTrue(packageScript.contains("SHA256SUMS"))
        XCTAssertTrue(packageScript.contains("release_notes_sha256"))
        XCTAssertTrue(packageScript.contains("release_notes_copy"))
        XCTAssertTrue(packageScript.contains("start_commit"))
        XCTAssertTrue(packageScript.contains("final_commit"))
        XCTAssertTrue(
            packageScript.contains(
                "git -C \"$ROOT_DIR\" archive --format=tar \"$start_commit\""
            )
        )
        XCTAssertTrue(
            packageScript.contains(
                "\"$source_snapshot/Scripts/package_dmg.sh\""
            )
        )
        XCTAssertTrue(packageScript.contains("source tree changed while update assets were being built"))
        XCTAssertTrue(packageScript.contains("release notes changed while update assets were being built"))
        XCTAssertTrue(packageScript.contains("refusing to overwrite different assets"))
        XCTAssertTrue(packageScript.contains("CANDIDATE_DIR"))
        XCTAssertTrue(packageScript.contains("publication: not uploaded"))
        XCTAssertFalse(packageScript.contains("gh release create"))
        for script in [packageScript, publishScript] {
            XCTAssertTrue(script.contains("SPARKLE_RELEASE_VERSION=\"2.9.2\""))
            XCTAssertTrue(
                script.contains(
                    "EXPECTED_SPARKLE_TOOLS_ARCHIVE_SHA256=\"b83e37436774556ed055e0244b297ef2c790e0737393bf65bf495fcbba6eed65\""
                )
            )
            XCTAssertTrue(script.contains("prepare_verified_sparkle_tools"))
            XCTAssertTrue(script.contains("SPARKLE_TOOLS_ARCHIVE_SHA256"))
            XCTAssertTrue(script.contains("GENERATE_APPCAST_SHA256"))
            XCTAssertTrue(script.contains("GENERATE_KEYS_SHA256"))
            XCTAssertTrue(script.contains("SIGN_UPDATE_SHA256"))
            XCTAssertFalse(
                script.contains(".build/artifacts/sparkle/Sparkle/bin")
            )
        }
        XCTAssertTrue(packageScript.contains("sparkle_tools_archive_sha256"))
        XCTAssertTrue(packageScript.contains("generate_appcast_sha256"))
        XCTAssertTrue(packageScript.contains("generate_keys_sha256"))
        XCTAssertTrue(packageScript.contains("sign_update_sha256"))

        XCTAssertTrue(publishScript.contains("gh auth status"))
        XCTAssertTrue(publishScript.contains("GH_REPOSITORY=\"leonthinking/SitRight\""))
        XCTAssertTrue(publishScript.contains("--repo \"$GH_REPOSITORY\""))
        XCTAssertTrue(publishScript.contains("validate_origin_url"))
        XCTAssertTrue(publishScript.contains("verify_remote_main_commit"))
        XCTAssertTrue(
            publishScript.contains(
                "remote main must resolve uniquely to the verified release commit"
            )
        )
        XCTAssertEqual(
            publishScript.components(
                separatedBy: "verify_remote_main_commit \\"
            ).count - 1,
            3
        )
        XCTAssertTrue(publishScript.contains("verify_remote_community_contract"))
        XCTAssertTrue(publishScript.contains("verify_remote_repository_contract"))
        XCTAssertTrue(
            publishScript.contains(
                "/repos/$GH_REPOSITORY/contents/$required_path?ref=main"
            )
        )
        XCTAssertTrue(publishScript.contains("--jq '.sha'"))
        XCTAssertTrue(
            publishScript.contains(
                "git -C \"$ROOT_DIR\" rev-parse \"HEAD:$required_path\""
            )
        )
        XCTAssertTrue(
            publishScript.contains(
                "merge $required_path into the remote main branch before publishing community links"
            )
        )
        XCTAssertTrue(
            publishScript.contains(
                "remote main must contain the exact verified $required_path before publishing community links"
            )
        )
        for requiredPath in [
            "PRIVACY.md",
            "SECURITY.md",
            "SUPPORT.md",
            "CONTRIBUTING.md",
            "Sources/Resources/SitRight-License.txt",
            "Sources/Resources/Third-Party-Notices.txt",
            ".github/PULL_REQUEST_TEMPLATE.md",
            ".github/ISSUE_TEMPLATE/config.yml",
            ".github/ISSUE_TEMPLATE/support_request.yml",
        ] {
            XCTAssertTrue(publishScript.contains(requiredPath))
        }
        XCTAssertTrue(publishScript.contains("\"private\""))
        XCTAssertTrue(publishScript.contains("\"visibility\""))
        XCTAssertTrue(publishScript.contains("\"default_branch\""))
        XCTAssertTrue(publishScript.contains("\"has_issues\""))
        XCTAssertTrue(
            publishScript.contains(
                "/repos/$GH_REPOSITORY/private-vulnerability-reporting"
            )
        )
        XCTAssertTrue(publishScript.contains("private_reporting.get(\"enabled\") is True"))
        XCTAssertTrue(
            publishScript.contains(
                "Private Vulnerability Reporting must be enabled"
            )
        )
        XCTAssertTrue(
            publishScript.contains(
                "$ROOT_DIR/Sources/Resources/SitRight-License.txt|SitRight-License.txt"
            )
        )
        XCTAssertTrue(
            publishScript.contains(
                "$ROOT_DIR/Sources/Resources/Third-Party-Notices.txt|Third-Party-Notices.txt"
            )
        )
        XCTAssertTrue(publishScript.contains("SITRIGHT_RELEASE_CONFIRMATION"))
        XCTAssertTrue(
            publishScript.contains(
                "SITRIGHT_SPARKLE_KEY_BACKUP_CONFIRMATION"
            )
        )
        XCTAssertTrue(publishScript.contains("SITRIGHT_RELEASE_NOTES_FILE"))
        XCTAssertTrue(publishScript.contains("git -C \"$ROOT_DIR\" ls-remote origin"))
        XCTAssertTrue(publishScript.contains("manifest_asset_name"))
        XCTAssertTrue(publishScript.contains("release notes differ from the copy embedded"))
        XCTAssertTrue(publishScript.contains("the release source tree must remain clean"))
        XCTAssertTrue(publishScript.contains("build $build_version must be newer"))
        XCTAssertTrue(publishScript.contains("SITRIGHT_BOOTSTRAP_CONFIRMATION"))
        XCTAssertTrue(publishScript.contains("verify_prepared_assets"))
        XCTAssertTrue(publishScript.contains("verify_checksum_contract"))
        XCTAssertTrue(publishScript.contains("verify_release_app"))
        XCTAssertTrue(publishScript.contains("verify_exact_entitlements"))
        XCTAssertTrue(publishScript.contains("immutable_release_dir"))
        XCTAssertTrue(publishScript.contains("immutable_notes_file"))
        XCTAssertTrue(publishScript.contains("github_api_json_or_404"))
        XCTAssertTrue(
            publishScript.contains(
                "\"/repos/$GH_REPOSITORY/releases/latest\""
            )
        )
        XCTAssertFalse(publishScript.contains("releases?per_page"))
        XCTAssertTrue(publishScript.contains("SURequireSignedFeed|true"))
        XCTAssertTrue(
            publishScript.contains("SUVerifyUpdateBeforeExtraction|true")
        )
        XCTAssertTrue(
            publishScript.contains(
                "SUSignedFeedFailureExpirationInterval|0"
            )
        )
        XCTAssertTrue(publishScript.contains("SUAutomaticallyUpdate|false"))
        XCTAssertTrue(publishScript.contains("SUAllowsAutomaticUpdates|false"))
        XCTAssertTrue(publishScript.contains("sign_update"))
        XCTAssertTrue(publishScript.contains("--verify"))
        XCTAssertTrue(publishScript.contains("gh release create \"$tag\""))
        XCTAssertTrue(publishScript.contains("gh release edit \"$tag\""))
        XCTAssertTrue(publishScript.contains("--verify-tag"))
        XCTAssertTrue(publishScript.contains("--json tagName,isDraft,isPrerelease,assets"))
        XCTAssertTrue(publishScript.contains("--draft"))
        XCTAssertTrue(publishScript.contains("--draft=false"))
        XCTAssertTrue(publishScript.contains("PUBLICATION_STATE_FILE"))
        XCTAssertTrue(publishScript.contains("write_publication_state"))
        XCTAssertTrue(publishScript.contains("recover_pending_publication"))
        XCTAssertTrue(publishScript.contains("recover_publication_to_draft"))
        XCTAssertTrue(
            publishScript.contains(
                "recover_pending_publication \"$tag\" \"$commit_sha\""
            )
        )
        XCTAssertTrue(
            publishScript.contains(
                "publication recovery state does not match the current release manifest"
            )
        )
        XCTAssertTrue(
            publishScript.contains(
                "publication recovery state does not match the remote tag"
            )
        )
        XCTAssertTrue(publishScript.contains("--draft=true"))
        XCTAssertTrue(
            publishScript.contains(
                "Release publication state is uncertain"
            )
        )
        XCTAssertFalse(publishScript.contains("--prerelease"))
        XCTAssertFalse(publishScript.contains("--clobber"))
        XCTAssertFalse(publishScript.contains("--force"))

        let draftCreation = try XCTUnwrap(
            publishScript.range(of: "gh release create \"$tag\"")
        )
        let communityGate = try XCTUnwrap(
            publishScript.range(of: "verify_remote_community_contract\n")
        )
        let repositoryGate = try XCTUnwrap(
            publishScript.range(of: "verify_remote_repository_contract\n")
        )
        let immutableVerification = try XCTUnwrap(
            publishScript.range(of: "verify_prepared_assets \\")
        )
        let draftVerification = try XCTUnwrap(
            publishScript.range(
                of: """
                verify_release_json \\
                    "$draft_release_json" \\
                    true
                """
            )
        )
        let publicationState = try XCTUnwrap(
            publishScript.range(
                of: "write_publication_state \"$tag\" \"$commit_sha\""
            )
        )
        let publication = try XCTUnwrap(
            publishScript.range(
                of: """
                gh release edit "$tag" \\
                    --repo "$GH_REPOSITORY" \\
                    --draft=false
                """
            )
        )
        let finalVerification = try XCTUnwrap(
            publishScript.range(
                of: """
                verify_release_json \\
                    "$release_json" \\
                    false
                """
            )
        )
        XCTAssertLessThan(
            immutableVerification.lowerBound,
            draftCreation.lowerBound
        )
        XCTAssertLessThan(communityGate.lowerBound, draftCreation.lowerBound)
        XCTAssertLessThan(repositoryGate.lowerBound, draftCreation.lowerBound)
        XCTAssertLessThan(draftCreation.lowerBound, draftVerification.lowerBound)
        XCTAssertLessThan(
            draftVerification.lowerBound,
            publicationState.lowerBound
        )
        XCTAssertLessThan(publicationState.lowerBound, publication.lowerBound)
        XCTAssertLessThan(publication.lowerBound, finalVerification.lowerBound)
        let clearPublicationState = try XCTUnwrap(
            publishScript.range(
                of: """
                PUBLICATION_IN_PROGRESS=0
                  PUBLICATION_TAG=""
                  clear_publication_state
                """
            )
        )
        XCTAssertLessThan(
            finalVerification.lowerBound,
            clearPublicationState.lowerBound
        )
    }

    func testRemoteCommunityContractRequiresExactMainBlobs() throws {
        let publishScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/publish_update_release.sh"
            ),
            encoding: .utf8
        )
        let runner = """
        set -euo pipefail
        MODE="$1"
        GH_REPOSITORY="leonthinking/SitRight"
        ROOT_DIR="/fixture"
        gh() {
          if [ "$MODE" = "missing" ] && [[ "$*" == *"bug_report.yml"* ]]; then
            return 1
          fi
          if [ "$MODE" = "mismatch" ] && [[ "$*" == *"feature_request.yml"* ]]; then
            echo "different-blob-sha"
          else
            echo "verified-blob-sha"
          fi
        }
        git() {
          echo "verified-blob-sha"
        }
        \(try function(named: "verify_remote_community_contract", in: publishScript))
        verify_remote_community_contract
        """

        XCTAssertEqual(
            try bashExitStatus(script: runner, arguments: ["matching"]),
            0
        )
        XCTAssertNotEqual(
            try bashExitStatus(script: runner, arguments: ["missing"]),
            0
        )
        XCTAssertNotEqual(
            try bashExitStatus(script: runner, arguments: ["mismatch"]),
            0
        )
    }

    func testRemoteRepositoryContractRequiresPublicMainIssuesAndPrivateReporting() throws {
        let publishScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/publish_update_release.sh"
            ),
            encoding: .utf8
        )
        let runner = """
        set -euo pipefail
        MODE="$1"
        GH_REPOSITORY="leonthinking/SitRight"
        gh() {
          if [[ "$*" == *"private-vulnerability-reporting"* ]]; then
            if [ "$MODE" = "reporting-unavailable" ]; then
              return 1
            fi
            if [ "$MODE" = "reporting-disabled" ]; then
              echo '{"enabled":false}'
            else
              echo '{"enabled":true}'
            fi
            return
          fi
          case "$MODE" in
            matching)
              echo '{"private":false,"visibility":"public","default_branch":"main","has_issues":true}'
              ;;
            private)
              echo '{"private":true,"visibility":"private","default_branch":"main","has_issues":true}'
              ;;
            wrong-branch)
              echo '{"private":false,"visibility":"public","default_branch":"develop","has_issues":true}'
              ;;
            no-issues)
              echo '{"private":false,"visibility":"public","default_branch":"main","has_issues":false}'
              ;;
            reporting-disabled | reporting-unavailable)
              echo '{"private":false,"visibility":"public","default_branch":"main","has_issues":true}'
              ;;
          esac
        }
        \(try function(named: "verify_remote_repository_contract", in: publishScript))
        verify_remote_repository_contract
        """

        XCTAssertEqual(
            try bashExitStatus(script: runner, arguments: ["matching"]),
            0
        )
        for mode in [
            "private",
            "wrong-branch",
            "no-issues",
            "reporting-disabled",
            "reporting-unavailable",
        ] {
            XCTAssertNotEqual(
                try bashExitStatus(script: runner, arguments: [mode]),
                0
            )
        }
    }

    func testRemoteMainContractRejectsMismatchAmbiguityAndLookupFailure() throws {
        let publishScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/publish_update_release.sh"
            ),
            encoding: .utf8
        )
        let runner = """
        set -euo pipefail
        MODE="$1"
        ROOT_DIR="/fixture"
        EXPECTED_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        git() {
          case "$MODE" in
            matching)
              echo "$EXPECTED_COMMIT refs/heads/main"
              ;;
            mismatch)
              echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb refs/heads/main"
              ;;
            ambiguous)
              echo "$EXPECTED_COMMIT refs/heads/main"
              echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb refs/heads/main"
              ;;
            missing)
              return 0
              ;;
            failure)
              return 1
              ;;
          esac
        }
        \(try function(named: "verify_remote_main_commit", in: publishScript))
        verify_remote_main_commit "$EXPECTED_COMMIT" "https://github.com/leonthinking/SitRight.git"
        """

        XCTAssertEqual(
            try bashExitStatus(script: runner, arguments: ["matching"]),
            0
        )
        for mode in ["mismatch", "ambiguous", "missing", "failure"] {
            XCTAssertNotEqual(
                try bashExitStatus(script: runner, arguments: [mode]),
                0
            )
        }
    }

    func testUpdateZIPValidationAcceptsOnlySitRightAppHierarchy() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/package_update.sh"
            ),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SitRightUpdateZIP-\(UUID().uuidString)",
                isDirectory: true
            )
        let validSource = temporaryDirectory.appendingPathComponent(
            "valid",
            isDirectory: true
        )
        let invalidSource = temporaryDirectory.appendingPathComponent(
            "invalid",
            isDirectory: true
        )
        let validZIP = temporaryDirectory.appendingPathComponent("valid.zip")
        let invalidZIP = temporaryDirectory.appendingPathComponent("invalid.zip")
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(
            at: validSource.appendingPathComponent(
                "SitRight.app/Contents/MacOS",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        try Data("app".utf8).write(
            to: validSource.appendingPathComponent(
                "SitRight.app/Contents/MacOS/SitRight"
            )
        )
        try FileManager.default.createDirectory(
            at: invalidSource.appendingPathComponent(
                "SitRight.app",
                isDirectory: true
            ),
            withIntermediateDirectories: true
        )
        try Data("app".utf8).write(
            to: invalidSource.appendingPathComponent("SitRight.app/SitRight")
        )
        try Data("extra".utf8).write(
            to: invalidSource.appendingPathComponent("unexpected.txt")
        )

        let archiveRunner = """
        set -euo pipefail
        cd "$1"
        /usr/bin/zip -q -r "$2" .
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: archiveRunner,
                arguments: [validSource.path, validZIP.path]
            ),
            0
        )
        XCTAssertEqual(
            try bashExitStatus(
                script: archiveRunner,
                arguments: [invalidSource.path, invalidZIP.path]
            ),
            0
        )

        let validationRunner = """
        set -euo pipefail
        \(try function(named: "verify_update_zip_contents", in: packageScript))
        verify_update_zip_contents "$1"
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: validationRunner,
                arguments: [validZIP.path]
            ),
            0
        )
        XCTAssertNotEqual(
            try bashExitStatus(
                script: validationRunner,
                arguments: [invalidZIP.path]
            ),
            0
        )
    }

    func testInterruptedPublicReleaseIsRecoveredToDraftOrRemainsBlocked() throws {
        let publishScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/publish_update_release.sh"
            ),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SitRightPublicationRecovery-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let sharedFunctions = """
        \(try function(named: "publication_state_value", in: publishScript))
        \(try function(named: "clear_publication_state", in: publishScript))
        \(try function(named: "recover_publication_to_draft", in: publishScript))
        \(try function(named: "recover_pending_publication", in: publishScript))
        \(try function(named: "write_publication_state", in: publishScript))
        """
        let recoveryRunner = """
        set -euo pipefail
        GH_REPOSITORY="leonthinking/SitRight"
        ROOT_DIR="$1"
        PUBLICATION_STATE_DIR="$1"
        PUBLICATION_STATE_FILE="$PUBLICATION_STATE_DIR/state"
        PUBLICATION_IN_PROGRESS=1
        PUBLICATION_TAG="v0.2.2"
        \(sharedFunctions)
        git() {
          echo '0123456789abcdef0123456789abcdef01234567 refs/tags/v0.2.2^{}'
        }
        gh() {
          if [ "$1" = "release" ] && [ "$2" = "view" ]; then
            if [ -f "$PUBLICATION_STATE_DIR/public" ]; then
              echo '{"tagName":"v0.2.2","isDraft":false,"isPrerelease":false}'
            else
              echo '{"tagName":"v0.2.2","isDraft":true,"isPrerelease":false}'
            fi
            return 0
          fi
          if [ "$1" = "release" ] && [ "$2" = "edit" ]; then
            /bin/rm -f "$PUBLICATION_STATE_DIR/public"
            /usr/bin/touch "$PUBLICATION_STATE_DIR/edit-called"
            return 0
          fi
          return 1
        }
        write_publication_state \
          "v0.2.2" \
          "0123456789abcdef0123456789abcdef01234567"
        /usr/bin/touch "$PUBLICATION_STATE_DIR/public"
        recover_pending_publication \
          "v0.2.2" \
          "0123456789abcdef0123456789abcdef01234567"
        [ ! -e "$PUBLICATION_STATE_FILE" ]
        [ ! -e "$PUBLICATION_STATE_DIR/public" ]
        [ -e "$PUBLICATION_STATE_DIR/edit-called" ]
        [ "$PUBLICATION_IN_PROGRESS" = "0" ]
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: recoveryRunner,
                arguments: [temporaryDirectory.path]
            ),
            0
        )

        let blockedDirectory = temporaryDirectory
            .appendingPathComponent("blocked", isDirectory: true)
        let blockedRunner = """
        set -euo pipefail
        GH_REPOSITORY="leonthinking/SitRight"
        ROOT_DIR="$1"
        PUBLICATION_STATE_DIR="$1"
        PUBLICATION_STATE_FILE="$PUBLICATION_STATE_DIR/state"
        PUBLICATION_IN_PROGRESS=1
        PUBLICATION_TAG="v0.2.2"
        \(sharedFunctions)
        git() {
          echo '0123456789abcdef0123456789abcdef01234567 refs/tags/v0.2.2^{}'
        }
        gh() {
          return 1
        }
        write_publication_state \
          "v0.2.2" \
          "0123456789abcdef0123456789abcdef01234567"
        if recover_pending_publication \
          "v0.2.2" \
          "0123456789abcdef0123456789abcdef01234567"; then
          exit 1
        fi
        [ -f "$PUBLICATION_STATE_FILE" ]
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: blockedRunner,
                arguments: [blockedDirectory.path]
            ),
            0
        )

        let mismatchedDirectory = temporaryDirectory
            .appendingPathComponent("mismatched", isDirectory: true)
        let mismatchedRunner = """
        set -euo pipefail
        GH_REPOSITORY="leonthinking/SitRight"
        ROOT_DIR="$1"
        PUBLICATION_STATE_DIR="$1"
        PUBLICATION_STATE_FILE="$PUBLICATION_STATE_DIR/state"
        PUBLICATION_IN_PROGRESS=1
        PUBLICATION_TAG="v0.2.2"
        \(sharedFunctions)
        git() {
          /usr/bin/touch "$PUBLICATION_STATE_DIR/git-called"
          return 1
        }
        gh() {
          /usr/bin/touch "$PUBLICATION_STATE_DIR/gh-called"
          return 1
        }
        write_publication_state \
          "v0.1.0" \
          "abcdef0123456789abcdef0123456789abcdef01"
        if recover_pending_publication \
          "v0.2.2" \
          "0123456789abcdef0123456789abcdef01234567"; then
          exit 1
        fi
        [ -f "$PUBLICATION_STATE_FILE" ]
        [ ! -e "$PUBLICATION_STATE_DIR/git-called" ]
        [ ! -e "$PUBLICATION_STATE_DIR/gh-called" ]
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: mismatchedRunner,
                arguments: [mismatchedDirectory.path]
            ),
            0
        )
    }

    func testDMGContentManifestDoesNotFollowFrameworkSymlinkLoopsAndDetectsTampering() throws {
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/package_dmg.sh"
            ),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SitRightTreeManifest-\(UUID().uuidString)",
                isDirectory: true
            )
        let staged = temporaryDirectory.appendingPathComponent(
            "staged",
            isDirectory: true
        )
        let mounted = temporaryDirectory.appendingPathComponent(
            "mounted",
            isDirectory: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        for root in [staged, mounted] {
            let version = root
                .appendingPathComponent("Framework/Versions/B", isDirectory: true)
            try FileManager.default.createDirectory(
                at: version,
                withIntermediateDirectories: true
            )
            try Data("signed-binary".utf8).write(
                to: version.appendingPathComponent("Sparkle")
            )
            try FileManager.default.createSymbolicLink(
                atPath: root
                    .appendingPathComponent("Framework/Versions/Current")
                    .path,
                withDestinationPath: "B"
            )
        }

        let compareRunner = """
        set -euo pipefail
        \(try function(named: "write_tree_manifest", in: packageScript))
        write_tree_manifest "$1" "$3"
        write_tree_manifest "$2" "$4"
        /usr/bin/diff -u "$3" "$4"
        """
        let firstManifest = temporaryDirectory.appendingPathComponent("first")
        let secondManifest = temporaryDirectory.appendingPathComponent("second")
        XCTAssertEqual(
            try bashExitStatus(
                script: compareRunner,
                arguments: [
                    staged.path,
                    mounted.path,
                    firstManifest.path,
                    secondManifest.path
                ]
            ),
            0
        )

        try Data("tampered-binary".utf8).write(
            to: mounted.appendingPathComponent(
                "Framework/Versions/B/Sparkle"
            )
        )
        XCTAssertNotEqual(
            try bashExitStatus(
                script: compareRunner,
                arguments: [
                    staged.path,
                    mounted.path,
                    firstManifest.path,
                    secondManifest.path
                ]
            ),
            0
        )
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

    func testDMGRequiresExactSandboxAppGroupAndSparkleMachEntitlements() throws {
        let expectedGroup = try XCTUnwrap(
            SharedStorage.appGroupIdentifiers.first
        )
        let validApp: [String: Any] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.application-groups": [expectedGroup],
            "com.apple.security.temporary-exception.mach-lookup.global-name": [
                "com.leon.SitRight-spki",
                "com.leon.SitRight-spks"
            ]
        ]
        let validWidget: [String: Any] = [
            "com.apple.security.app-sandbox": true,
            "com.apple.security.application-groups": [expectedGroup]
        ]
        var missingSandbox = validApp
        missingSandbox.removeValue(
            forKey: "com.apple.security.app-sandbox"
        )
        var extraGroup = validApp
        extraGroup["com.apple.security.application-groups"] = [
            expectedGroup,
            "973KFG9CL9.com.leon.Unexpected"
        ]
        var wrongMachService = validApp
        wrongMachService[
            "com.apple.security.temporary-exception.mach-lookup.global-name"
        ] = [
            "com.leon.SitRight-spki",
            "com.leon.SitRight-wrong"
        ]
        var widgetWithMachService = validWidget
        widgetWithMachService[
            "com.apple.security.temporary-exception.mach-lookup.global-name"
        ] = ["com.leon.SitRight-spki"]

        XCTAssertEqual(
            try updateEntitlementValidationExitStatus(
                for: validApp,
                role: "app"
            ),
            0
        )
        XCTAssertEqual(
            try updateEntitlementValidationExitStatus(
                for: validWidget,
                role: "widget"
            ),
            0
        )
        for invalidApp in [missingSandbox, extraGroup, wrongMachService] {
            XCTAssertNotEqual(
                try updateEntitlementValidationExitStatus(
                    for: invalidApp,
                    role: "app"
                ),
                0
            )
        }
        XCTAssertNotEqual(
            try updateEntitlementValidationExitStatus(
                for: widgetWithMachService,
                role: "widget"
            ),
            0
        )
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

    func testCompetingWidgetRegistrationCleanupParsesDuplicatePhysicalPaths() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightPlugInKitFixture-\(UUID().uuidString)", isDirectory: true)
        let plugInKitURL = temporaryDirectory.appendingPathComponent("pluginkit")
        let launchServicesURL = temporaryDirectory.appendingPathComponent("lsregister")
        let eventsURL = temporaryDirectory.appendingPathComponent("events.log")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let canonicalWidget = "/Applications/SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex"
        let duplicateWidget = "/tmp/Old Build/SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex"
        let secondDuplicateWidget = "/tmp/Second Build/SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex"
        let plugInKitFixture = """
        #!/bin/bash
        set -euo pipefail
        if [ "$1" = "-m" ]; then
          /usr/bin/printf 'query:%s\n' "$*" >>"$SITRIGHT_TEST_LOG"
          /usr/bin/printf ' bundle(0.2.5)\tUUID-A\tDATE\t%s\n' "$SITRIGHT_CANONICAL_WIDGET"
          /usr/bin/printf ' bundle(0.2.5) UUID-B DATE %s\n' "$SITRIGHT_DUPLICATE_WIDGET"
          /usr/bin/printf ' bundle(0.2.5)\tUUID-C\tDATE\t%s\n' "$SITRIGHT_SECOND_DUPLICATE_WIDGET"
          /usr/bin/printf ' (3 plug-ins)\n'
          exit 0
        fi
        if [ "$1" = "-r" ]; then
          /usr/bin/printf 'remove:%s\n' "$2" >>"$SITRIGHT_TEST_LOG"
          exit 0
        fi
        exit 64
        """
        let launchServicesFixture = """
        #!/bin/bash
        set -euo pipefail
        /usr/bin/printf 'lsregister:%s\n' "$*" >>"$SITRIGHT_TEST_LOG"
        """
        try plugInKitFixture.write(to: plugInKitURL, atomically: true, encoding: .utf8)
        try launchServicesFixture.write(
            to: launchServicesURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: plugInKitURL.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launchServicesURL.path
        )

        let runner = """
        set -euo pipefail
        PLUGINKIT="$1/pluginkit"
        LSREGISTER="$1/lsregister"
        WIDGET_BUNDLE_IDENTIFIER="com.leon.SitRight.SitRightWidgetExtension"
        SITRIGHT_TEST_LOG="$1/events.log"
        SITRIGHT_CANONICAL_WIDGET="$2"
        SITRIGHT_DUPLICATE_WIDGET="$3"
        SITRIGHT_SECOND_DUPLICATE_WIDGET="$4"
        export SITRIGHT_TEST_LOG SITRIGHT_CANONICAL_WIDGET SITRIGHT_DUPLICATE_WIDGET
        export SITRIGHT_SECOND_DUPLICATE_WIDGET
        \(try function(named: "unregister_competing_widget_registrations", in: buildScript))
        unregister_competing_widget_registrations "$SITRIGHT_CANONICAL_WIDGET"
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: runner,
                arguments: [
                    temporaryDirectory.path,
                    canonicalWidget,
                    duplicateWidget,
                    secondDuplicateWidget,
                ]
            ),
            0
        )

        let events = try String(contentsOf: eventsURL, encoding: .utf8)
        XCTAssertTrue(events.contains("query:-m -A -D -v -i com.leon.SitRight.SitRightWidgetExtension"))
        XCTAssertTrue(events.contains("remove:\(duplicateWidget)"))
        XCTAssertTrue(events.contains("remove:\(secondDuplicateWidget)"))
        XCTAssertFalse(events.contains("remove:\(canonicalWidget)"))
        XCTAssertTrue(events.contains("lsregister:-u /tmp/Old Build/SitRight.app"))
        XCTAssertTrue(events.contains("lsregister:-u /tmp/Second Build/SitRight.app"))
    }

    func testInstallOutputGuardNormalizesMissingParentTraversal() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let runner = """
        set -euo pipefail
        \(try function(named: "normalize_absolute_path_lexically", in: buildScript))
        \(try function(named: "canonical_path_allowing_missing", in: buildScript))
        test "$(canonical_path_allowing_missing "$1")" = "$(canonical_path_allowing_missing "$2")"
        """
        XCTAssertEqual(
            try bashExitStatus(
                script: runner,
                arguments: [
                    "/Applications/sitright-parent-that-does-not-exist/../SitRight.app",
                    "/Applications/SitRight.app",
                ]
            ),
            0
        )
    }

    func testInstallOutputGuardRejectsParentTraversalThroughSymlink() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightOutputTraversal-\(UUID().uuidString)", isDirectory: true)
        let applicationsDirectory = temporaryDirectory.appendingPathComponent("Applications", isDirectory: true)
        let utilitiesDirectory = applicationsDirectory.appendingPathComponent("Utilities", isDirectory: true)
        let linksDirectory = temporaryDirectory.appendingPathComponent("Links", isDirectory: true)
        let outputLink = linksDirectory.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: utilitiesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linksDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: outputLink, withDestinationURL: utilitiesDirectory)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let traversalPath = outputLink
            .appendingPathComponent("..")
            .appendingPathComponent("SitRight.app")
            .path
        let runner = """
        set -euo pipefail
        \(try function(named: "path_has_parent_traversal", in: buildScript))
        path_has_parent_traversal "$1"
        """
        XCTAssertEqual(
            try bashExitStatus(script: runner, arguments: [traversalPath]),
            0
        )
    }

    func testInstalledWidgetRegistrationRequiresThreeConsecutiveUniqueObservations() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightStableRegistration-\(UUID().uuidString)", isDirectory: true)
        let plugInKitURL = temporaryDirectory.appendingPathComponent("pluginkit")
        let launchServicesURL = temporaryDirectory.appendingPathComponent("lsregister")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let plugInKitFixture = """
        #!/bin/bash
        set -euo pipefail
        if [ "$1" = "-m" ]; then
          count=0
          if [ -f "$SITRIGHT_QUERY_COUNT" ]; then
            count="$(/bin/cat "$SITRIGHT_QUERY_COUNT")"
          fi
          count=$((count + 1))
          /usr/bin/printf '%s\n' "$count" >"$SITRIGHT_QUERY_COUNT"
          /usr/bin/printf ' bundle(0.2.5) UUID-A DATE %s\n' "$SITRIGHT_CANONICAL_WIDGET"
          if [ "$SITRIGHT_SEQUENCE" = "late-duplicate" ] && [ "$count" = "3" ]; then
            /usr/bin/printf ' bundle(0.2.5) UUID-B DATE %s\n' "$SITRIGHT_DUPLICATE_WIDGET"
          elif [ "$SITRIGHT_SEQUENCE" = "unstable" ] && [ "$count" -gt 1 ] && [ $((count % 2)) = 1 ]; then
            /usr/bin/printf ' bundle(0.2.5) UUID-B DATE %s\n' "$SITRIGHT_DUPLICATE_WIDGET"
          fi
          exit 0
        fi
        if [ "$1" = "-a" ] || [ "$1" = "-r" ]; then
          exit 0
        fi
        exit 64
        """
        let launchServicesFixture = """
        #!/bin/bash
        set -euo pipefail
        exit 0
        """
        try plugInKitFixture.write(to: plugInKitURL, atomically: true, encoding: .utf8)
        try launchServicesFixture.write(to: launchServicesURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plugInKitURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchServicesURL.path)

        let runner = """
        set -euo pipefail
        PLUGINKIT="$1/pluginkit"
        LSREGISTER="$1/lsregister"
        WIDGET_BUNDLE_IDENTIFIER="com.leon.SitRight.SitRightWidgetExtension"
        SITRIGHT_CANONICAL_WIDGET="$2"
        SITRIGHT_DUPLICATE_WIDGET="$3"
        SITRIGHT_SEQUENCE="$4"
        SITRIGHT_QUERY_COUNT="$1/query-count"
        SITRIGHT_WIDGET_REGISTRATION_POLL_INTERVAL=0
        export SITRIGHT_CANONICAL_WIDGET SITRIGHT_DUPLICATE_WIDGET SITRIGHT_SEQUENCE
        export SITRIGHT_QUERY_COUNT SITRIGHT_WIDGET_REGISTRATION_POLL_INTERVAL
        \(try function(named: "unregister_competing_widget_registrations", in: buildScript))
        \(try function(named: "register_installed_app", in: buildScript))
        register_installed_app "/Applications/SitRight.app"
        """
        let canonicalWidget = "/Applications/SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex"
        let duplicateWidget = "/tmp/Late SitRight.app/Contents/PlugIns/SitRightWidgetExtension.appex"

        XCTAssertEqual(
            try bashExitStatus(
                script: runner,
                arguments: [temporaryDirectory.path, canonicalWidget, duplicateWidget, "late-duplicate"]
            ),
            0
        )
        XCTAssertEqual(
            try String(
                contentsOf: temporaryDirectory.appendingPathComponent("query-count"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            "6"
        )

        try FileManager.default.removeItem(
            at: temporaryDirectory.appendingPathComponent("query-count")
        )
        XCTAssertNotEqual(
            try bashExitStatus(
                script: runner,
                arguments: [temporaryDirectory.path, canonicalWidget, duplicateWidget, "unstable"]
            ),
            0
        )
        XCTAssertEqual(
            try String(
                contentsOf: temporaryDirectory.appendingPathComponent("query-count"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            "9"
        )
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
        stop_running_sitright_processes() { :; }
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

    func testInterruptedApplicationInstallPreservesTransactionWhenProcessesCannotStop() throws {
        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Scripts/build_app.sh"),
            encoding: .utf8
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SitRightBlockedRecovery-\(UUID().uuidString)", isDirectory: true)
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
        stop_running_sitright_processes() { return 1; }
        \(try function(named: "write_install_transaction_state", in: buildScript))
        \(try function(named: "rollback_installation_transaction", in: buildScript))
        rollback_installation_transaction
        """
        XCTAssertNotEqual(
            try bashExitStatus(script: runner, arguments: [temporaryDirectory.path]),
            0
        )
        XCTAssertEqual(
            try String(
                contentsOf: installApp.appendingPathComponent("marker"),
                encoding: .utf8
            ),
            "new-app"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: transactionDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousApp.path))
    }

    private func plist(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func plistJSON(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try JSONSerialization.jsonObject(with: data)
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

    private func updateEntitlementValidationExitStatus(
        for entitlements: [String: Any],
        role: String
    ) throws -> Int32 {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SitRightUpdateEntitlements-\(UUID().uuidString)",
                isDirectory: true
            )
        let entitlementsURL = temporaryDirectory.appendingPathComponent(
            "entitlements.plist"
        )
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
        let packageScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/package_dmg.sh"
            ),
            encoding: .utf8
        )
        let runner = """
        set -euo pipefail
        APP_GROUP_IDENTIFIER="\(try XCTUnwrap(SharedStorage.appGroupIdentifiers.first))"
        EXPECTED_INSTALLER_MACH_SERVICE="com.leon.SitRight-spki"
        EXPECTED_STATUS_MACH_SERVICE="com.leon.SitRight-spks"
        \(try function(named: "validate_update_entitlements_xml", in: packageScript))
        validate_update_entitlements_xml "$(/bin/cat "$1")" "Fixture" "$2"
        """
        return try bashExitStatus(
            script: runner,
            arguments: [entitlementsURL.path, role]
        )
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
