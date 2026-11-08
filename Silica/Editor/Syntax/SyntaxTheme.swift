import AppKit

/// Syntax colors from Atom's One Light (light appearance) and One Dark (dark appearance).
nonisolated enum SyntaxTheme {
    static let plain = NSColor.labelColor

    /// Gutter numbers: solid colors rather than translucent label colors, which
    /// lose contrast on the glass card.
    static let lineNumber = dynamic(light: 0x9A9AA0, dark: 0x9C9CA2)
    static let currentLineNumber = dynamic(light: 0x3C3C43, dark: 0xF2F2F7)

    /// Indent guides: a faint line that reads on the glass card in both appearances.
    static let indentGuide = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(white: 0, alpha: 0.10)
    }

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

    // Atom's One Light / One Dark palettes:
    //   One Light: purple A626A4, blue 4078F2, red E45649, green 50A14F,
    //              orange 986801, yellow C18401, cyan 0184BC, comment A0A1A7
    //   One Dark:  purple C678DD, blue 61AFEF, red E06C75, green 98C379,
    //              orange D19A66, yellow E5C07B, cyan 56B6C2, comment 5C6370 (see `gray`)
    private static let purple = (light: 0xA626A4 as UInt32, dark: 0xC678DD as UInt32)
    private static let blue = (light: 0x4078F2 as UInt32, dark: 0x61AFEF as UInt32)
    private static let red = (light: 0xE45649 as UInt32, dark: 0xE06C75 as UInt32)
    private static let green = (light: 0x50A14F as UInt32, dark: 0x98C379 as UInt32)
    private static let orange = (light: 0x986801 as UInt32, dark: 0xD19A66 as UInt32)
    private static let yellow = (light: 0xC18401 as UInt32, dark: 0xE5C07B as UInt32)
    private static let cyan = (light: 0x0184BC as UInt32, dark: 0x56B6C2 as UInt32)
    // One Dark's comment gray (5C6370) is meant for a near-black background and
    // nearly vanishes on the glass card, so dark mode uses a lighter shade of it.
    private static let gray = (light: 0xA0A1A7 as UInt32, dark: 0x9DA5B3 as UInt32)

    private static let keyword = dynamic(purple)
    private static let type = dynamic(yellow)
    private static let string = dynamic(green)
    private static let number = dynamic(orange)
    private static let comment = dynamic(gray)
    private static let attribute = dynamic(orange)
    private static let preprocessor = dynamic(purple)
    private static let function = dynamic(blue)
    private static let property = dynamic(red)
    private static let tag = dynamic(red)
    private static let variable = dynamic(red)
    private static let heading = dynamic(red)
    private static let link = dynamic(cyan)

    private static func dynamic(_ pair: (light: UInt32, dark: UInt32)) -> NSColor {
        dynamic(light: pair.light, dark: pair.dark)
    }

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
