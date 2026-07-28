import AppKit
import CryptoKit
import Foundation
import SwiftUI
import XCTest
@testable import SitRight

final class CommunityConfigurationTests: XCTestCase {
    func testCommunityLinksStayOnThePublicSitRightRepository() {
        XCTAssertEqual(
            CommunityLinks.repositoryURL.absoluteString,
            "https://github.com/leonthinking/SitRight"
        )
        XCTAssertEqual(
            CommunityLinks.releasesURL.absoluteString,
            "https://github.com/leonthinking/SitRight/releases"
        )
        XCTAssertEqual(
            CommunityLinks.starURL,
            CommunityLinks.repositoryURL
        )
        XCTAssertEqual(
            CommunityLinks.featureRequestURL.absoluteString,
            "https://github.com/leonthinking/SitRight/issues/new?template=feature_request.yml"
        )
        XCTAssertEqual(
            CommunityLinks.bugReportURL.absoluteString,
            "https://github.com/leonthinking/SitRight/issues/new?template=bug_report.yml"
        )
        XCTAssertEqual(
            CommunityLinks.supportRequestURL.absoluteString,
            "https://github.com/leonthinking/SitRight/issues/new?template=support_request.yml"
        )
        XCTAssertEqual(
            CommunityLinks.privacyURL.absoluteString,
            "https://github.com/leonthinking/SitRight/blob/main/PRIVACY.md"
        )
        XCTAssertEqual(
            CommunityLinks.securityReportURL.absoluteString,
            "https://github.com/leonthinking/SitRight/security/advisories/new"
        )
        XCTAssertEqual(
            UpdateConfiguration.releasesURL,
            CommunityLinks.releasesURL
        )
    }

    func testBundledMITLicenseMatchesRepositoryLicense() throws {
        let repositoryLicense = try String(
            contentsOf: repositoryRoot.appendingPathComponent("LICENSE"),
            encoding: .utf8
        )
        let bundledLicense = try LegalNoticeLoader.text(for: .sitRight)

        XCTAssertEqual(bundledLicense, repositoryLicense)
        XCTAssertTrue(bundledLicense.hasPrefix("MIT License"))
        XCTAssertTrue(bundledLicense.contains("Copyright (c) 2026 Leon Zhang"))
        XCTAssertTrue(
            bundledLicense.contains(
                "The above copyright notice and this permission notice"
            )
        )
    }

    func testBundledThirdPartyNoticeCoversSparkleAndEmbeddedLicenses() throws {
        let notice = try LegalNoticeLoader.text(for: .thirdParty)
        let digest = SHA256.hash(data: Data(notice.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertEqual(
            digest,
            "2f1bd0194a72d1f7cdbb9f86d3a613894d334822ac96d65fce11f3ac96f06a56"
        )
        XCTAssertTrue(notice.contains("Sparkle 2.9.2"))
        XCTAssertTrue(notice.contains("Copyright (c) 2006-2013 Andy Matuschak"))
        XCTAssertTrue(notice.contains("bspatch.c and bsdiff.c"))
        XCTAssertTrue(notice.contains("sais.c and sais.h"))
        XCTAssertTrue(notice.contains("Portable C implementation of Ed25519"))
        XCTAssertTrue(notice.contains("SUSignatureVerifier.m"))
    }

    func testLegalNoticeFallbacksStayOnReviewedLicenseSources() {
        XCTAssertEqual(
            LegalNotice.sitRight.fallbackURL.absoluteString,
            "https://github.com/leonthinking/SitRight/blob/main/LICENSE"
        )
        XCTAssertEqual(
            LegalNotice.thirdParty.fallbackURL.absoluteString,
            "https://github.com/sparkle-project/Sparkle/blob/2.9.2/LICENSE"
        )
    }

    @MainActor
    func testProductionLegalNoticeSheetsHaveStableNonZeroContentSize() {
        for notice in [LegalNotice.sitRight, .thirdParty] {
            let hostingController = NSHostingController(
                rootView: LegalNoticeSheet(notice: notice)
            )
            hostingController.sizingOptions = []
            let fittedSize = hostingController.sizeThatFits(
                in: NSSize(width: 900, height: 900)
            )

            XCTAssertGreaterThanOrEqual(
                fittedSize.width,
                LegalNoticeSheet.minimumContentSize.width
            )
            XCTAssertGreaterThanOrEqual(
                fittedSize.height,
                LegalNoticeSheet.minimumContentSize.height
            )
        }
    }

    func testGitHubIssueFormsMatchInAppDestinationsAndRequirePrivacyCheck() throws {
        let issueTemplateDirectory = repositoryRoot
            .appendingPathComponent(".github/ISSUE_TEMPLATE")
        let featureForm = try String(
            contentsOf: issueTemplateDirectory.appendingPathComponent(
                "feature_request.yml"
            ),
            encoding: .utf8
        )
        let bugForm = try String(
            contentsOf: issueTemplateDirectory.appendingPathComponent(
                "bug_report.yml"
            ),
            encoding: .utf8
        )
        let config = try String(
            contentsOf: issueTemplateDirectory.appendingPathComponent(
                "config.yml"
            ),
            encoding: .utf8
        )
        let supportForm = try String(
            contentsOf: issueTemplateDirectory.appendingPathComponent(
                "support_request.yml"
            ),
            encoding: .utf8
        )

        XCTAssertEqual(
            CommunityLinks.featureRequestURL.query,
            "template=feature_request.yml"
        )
        XCTAssertEqual(
            CommunityLinks.bugReportURL.query,
            "template=bug_report.yml"
        )
        XCTAssertTrue(featureForm.contains("id: problem"))
        XCTAssertTrue(featureForm.contains("id: outcome"))
        XCTAssertTrue(bugForm.contains("id: version"))
        XCTAssertTrue(bugForm.contains("id: macos"))
        XCTAssertTrue(bugForm.contains("id: steps"))
        XCTAssertTrue(bugForm.contains("id: frequency"))
        XCTAssertTrue(bugForm.contains("id: last_seen"))
        XCTAssertTrue(bugForm.contains("间歇"))
        XCTAssertTrue(supportForm.contains("id: topic"))
        XCTAssertTrue(supportForm.contains("id: question"))
        XCTAssertTrue(supportForm.contains("id: privacy"))
        XCTAssertTrue(featureForm.contains("id: privacy"))
        XCTAssertTrue(bugForm.contains("id: privacy"))
        XCTAssertTrue(featureForm.contains("required: true"))
        XCTAssertTrue(bugForm.contains("required: true"))
        XCTAssertTrue(bugForm.contains("不会自动上传"))
        XCTAssertTrue(config.contains("blank_issues_enabled: false"))
        XCTAssertTrue(config.contains("security/advisories/new"))
    }

    func testCommunityHealthDocumentsDescribePublicAndPrivateBoundaries() throws {
        let privacy = try text(at: "PRIVACY.md")
        let security = try text(at: "SECURITY.md")
        let support = try text(at: "SUPPORT.md")
        let contributing = try text(at: "CONTRIBUTING.md")
        let pullRequestTemplate = try text(
            at: ".github/PULL_REQUEST_TEMPLATE.md"
        )

        XCTAssertTrue(privacy.contains("不自动采集或上传崩溃报告"))
        XCTAssertTrue(privacy.contains("提醒设置和提醒会话状态保存在主应用"))
        XCTAssertTrue(privacy.contains("活动历史和 Widget 快照保存在 App Group"))
        XCTAssertTrue(privacy.contains("GitHub"))
        XCTAssertTrue(security.contains("Private Vulnerability Reporting"))
        XCTAssertTrue(security.contains("不要在公开 Issue"))
        XCTAssertTrue(support.contains("support_request.yml"))
        XCTAssertTrue(contributing.contains("swift test --disable-sandbox"))
        XCTAssertTrue(pullRequestTemplate.contains("真实活动数据"))
    }

    func testPackageDeclaresBundledLegalResources() throws {
        let packageManifest = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let info = try PropertyListSerialization.propertyList(
            from: Data(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "AppBundle/Info.plist"
                )
            ),
            options: [],
            format: nil
        ) as? [String: Any]

        XCTAssertTrue(packageManifest.contains(".copy(\"Resources\")"))
        XCTAssertEqual(
            info?["NSHumanReadableCopyright"] as? String,
            "Copyright © 2026 Leon Zhang. MIT License."
        )

        let buildScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Scripts/build_app.sh"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(buildScript.contains("verify_legal_resources()"))
        XCTAssertTrue(buildScript.contains("SitRight-License.txt"))
        XCTAssertTrue(buildScript.contains("Third-Party-Notices.txt"))
        XCTAssertTrue(buildScript.contains("/usr/bin/cmp -s"))
        XCTAssertTrue(
            buildScript.contains(
                "verify_legal_resources \"$app_path\" \"Build output SitRight.app\""
            )
        )
        XCTAssertTrue(
            buildScript.contains(
                "verify_legal_resources \"$APP_PATH\" \"Published SitRight.app\""
            )
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func text(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
