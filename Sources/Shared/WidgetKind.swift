enum SitRightWidgetKind {
    // Reserved forever so a future Widget cannot silently take over an installed
    // annual Widget's identity after that configuration was retired.
    static let retiredAnnualActivity = "SitRightActivityWidget"
    static let quarterActivity = "SitRightQuarterActivityWidget"

    static let allActivityKinds = [quarterActivity]
}
