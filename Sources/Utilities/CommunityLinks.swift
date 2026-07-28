import Foundation

enum CommunityLinks {
    static let repositoryURL = URL(
        string: "https://github.com/leonthinking/SitRight"
    )!
    static let releasesURL = repositoryURL.appending(
        path: "releases",
        directoryHint: .notDirectory
    )
    static let starURL = repositoryURL
    static let featureRequestURL = URL(
        string: "https://github.com/leonthinking/SitRight/issues/new?template=feature_request.yml"
    )!
    static let bugReportURL = URL(
        string: "https://github.com/leonthinking/SitRight/issues/new?template=bug_report.yml"
    )!
    static let supportRequestURL = URL(
        string: "https://github.com/leonthinking/SitRight/issues/new?template=support_request.yml"
    )!
    static let privacyURL = repositoryURL.appending(
        path: "blob/main/PRIVACY.md",
        directoryHint: .notDirectory
    )
    static let securityPolicyURL = repositoryURL.appending(
        path: "blob/main/SECURITY.md",
        directoryHint: .notDirectory
    )
    static let securityReportURL = repositoryURL.appending(
        path: "security/advisories/new",
        directoryHint: .notDirectory
    )
}
