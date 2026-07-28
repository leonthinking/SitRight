import Foundation

enum LegalNotice: String, Identifiable {
    case sitRight
    case thirdParty

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .sitRight:
            return "MIT 开源协议"
        case .thirdParty:
            return "第三方许可"
        }
    }

    fileprivate var resourceName: String {
        switch self {
        case .sitRight:
            return "SitRight-License"
        case .thirdParty:
            return "Third-Party-Notices"
        }
    }

    var fallbackURL: URL {
        switch self {
        case .sitRight:
            return URL(
                string: "https://github.com/leonthinking/SitRight/blob/main/LICENSE"
            )!
        case .thirdParty:
            return URL(
                string: "https://github.com/sparkle-project/Sparkle/blob/2.9.2/LICENSE"
            )!
        }
    }
}

enum LegalNoticeLoader {
    static func text(
        for notice: LegalNotice,
        bundle: Bundle = resourceBundle
    ) throws -> String {
        guard let url = bundle.url(
            forResource: notice.resourceName,
            withExtension: "txt",
            subdirectory: "Resources"
        ) ?? bundle.url(
            forResource: notice.resourceName,
            withExtension: "txt"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }
}
