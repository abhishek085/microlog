import SwiftUI

enum Theme {
    // Container
    static let containerWidth: CGFloat = 340
    static let containerHeight: CGFloat = 420
    static let containerRadius: CGFloat = 12
    static let backgroundOpacity: Double = 0.55

    // Cards
    static let cardRadius: CGFloat = 10
    static let headerCardRadius: CGFloat = 12
    static let cardVerticalPadding: CGFloat = 8
    static let cardHorizontalPadding: CGFloat = 10
    static let cardGap: CGFloat = 6
    static let headerCardPadding: CGFloat = 10
    static let outerHorizontalPadding: CGFloat = 12

    // Type sizes
    static let labelSize: CGFloat = 9
    static let captionSizeSmall: CGFloat = 10
    static let captionSize: CGFloat = 11
    static let bodySize: CGFloat = 12
    static let titleSize: CGFloat = 13
    static let detailTitleSize: CGFloat = 15

    // Timestamp / count monospaced
    static let monoSize: CGFloat = 11

    // Icons
    static let iconSmall: CGFloat = 11
    static let iconMedium: CGFloat = 13

    // Hit areas
    static let minHit: CGFloat = 24
    static let gearHit: CGFloat = 24

    // Note row
    static let rowHeight: CGFloat = 46
    static let timestampWidth: CGFloat = 40

    // Detail
    static let detailPadding: CGFloat = 12

    // Strings
    static let emptyTitle = "Nothing noted yet"
    static let emptyCaption = "Notes appear here as you read."
}
