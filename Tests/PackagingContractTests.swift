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
        XCTAssertTrue(buildScript.contains("trap cleanup EXIT"))
        XCTAssertTrue(buildScript.contains("SITRIGHT_KEEP_DERIVED_DATA"))
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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
