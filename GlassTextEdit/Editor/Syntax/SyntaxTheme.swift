import AppKit

/// Xcode-inspired colors that adapt to light and dark appearance.
nonisolated enum SyntaxTheme {
    static let plain = NSColor.labelColor

    static func color(for kind: TokenKind) -> NSColor {
        switch kind {
        case .keyword: keyword
        case .type: type
        case .string: string
        case .number: number
        case .comment: comment
        case .attribute: attribute
        case .preprocessor: preprocessor
        case .function: function
        case .property: property
        case .tag: tag
        case .variable: variable
        case .heading: heading
        case .link: link
        }
    }

    private static let keyword = dynamic(light: 0x9B2393, dark: 0xFC5FA3)
    private static let type = dynamic(light: 0x0B4F79, dark: 0x5DD8FF)
    private static let string = dynamic(light: 0xC41A16, dark: 0xFC6A5D)
    private static let number = dynamic(light: 0x1C00CF, dark: 0xD0BF69)
    private static let comment = dynamic(light: 0x5D6C79, dark: 0x9AA5B1)
    private static let attribute = dynamic(light: 0x815F03, dark: 0xD39A64)
    private static let preprocessor = dynamic(light: 0x643820, dark: 0xFD8F3F)
    private static let function = dynamic(light: 0x326D74, dark: 0x67B7A4)
    private static let property = dynamic(light: 0x3E6D9C, dark: 0x9CDCFE)
    private static let tag = dynamic(light: 0x0F68A0, dark: 0x5DD8FF)
    private static let variable = dynamic(light: 0x326D74, dark: 0x67B7A4)
    private static let heading = dynamic(light: 0x9B2393, dark: 0xFC5FA3)
    private static let link = dynamic(light: 0x0E0EFF, dark: 0x6699FF)

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
