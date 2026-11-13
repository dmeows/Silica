import Foundation

/// Turns delimited text (CSV, TSV) into an HTML table for the preview.
///
/// The first row becomes the table's header, and columns that hold only numbers are
/// aligned right. Each later row is tagged with `data-line` (the 1-based source line
/// it starts on) so the preview can scroll to, and report, a position in the source.
nonisolated enum CSVHTMLRenderer {
    /// Cells rendered before the table is cut short. A web view lays a table out all
    /// at once, and slows down long before a file reaches the editor's size limit.
    static let maxCells = 200_000

    /// `delimiter` is `nil` to tell commas, semicolons and tabs apart from the first row.
    static func render(_ text: String, delimiter: Character? = nil) -> String {
        let table = CSVTable(parsing: text, delimiter: delimiter?.utf16.first, maxCells: maxCells)
        guard let header = table.rows.first else {
            return "<p class=\"note\">No rows to show.</p>\n"
        }
        let rows = table.rows.dropFirst()
        // Rows can differ in length; short ones are filled out with empty cells.
        let columnCount = table.rows.reduce(0) { max($0, $1.fields.count) }
        let numericColumns = (0..<columnCount).map { column -> Bool in
            var hasNumber = false
            for row in rows where column < row.fields.count {
                let field = row.fields[column].trimmingCharacters(in: .whitespaces)
                if field.isEmpty { continue }
                guard isNumber(field) else { return false }
                hasNumber = true
            }
            return hasNumber
        }

        func cells(_ tag: String, _ fields: [String]) -> String {
            var html = ""
            for column in 0..<columnCount {
                let field = column < fields.count ? fields[column] : ""
                html += numericColumns[column] ? "<\(tag) class=\"num\">" : "<\(tag)>"
                html += MarkdownHTMLRenderer.escape(field)
                html += "</\(tag)>"
            }
            return html
        }

        var html = "<table>\n<thead><tr>\(cells("th", header.fields))</tr></thead>\n<tbody>\n"
        for row in rows {
            html += "<tr data-line=\"\(row.line)\">\(cells("td", row.fields))</tr>\n"
        }
        html += "</tbody>\n</table>\n"
        if table.rowCount > table.rows.count {
            // Counted without the header row.
            let shown = (table.rows.count - 1).formatted()
            let total = (table.rowCount - 1).formatted()
            html += "<p class=\"note\">Showing the first \(shown) of \(total) rows.</p>\n"
        }
        return html
    }

    /// A plain decimal number, as a spreadsheet would align right: `-12`, `1,250.50`,
    /// `3e-9`, `45%`.
    private static func isNumber(_ field: String) -> Bool {
        let bytes = Array(field.utf8)
        func isDigit(_ index: Int) -> Bool {
            index < bytes.count && bytes[index] >= UInt8(ascii: "0") && bytes[index] <= UInt8(ascii: "9")
        }
        func isOne(of characters: String, _ index: Int) -> Bool {
            index < bytes.count && characters.utf8.contains(bytes[index])
        }

        var index = 0
        var digitCount = 0
        if isOne(of: "+-", index) { index += 1 }
        // Commas group thousands.
        while isDigit(index) || (digitCount > 0 && isOne(of: ",", index) && isDigit(index + 1)) {
            if isDigit(index) { digitCount += 1 }
            index += 1
        }
        if isOne(of: ".", index) {
            index += 1
            while isDigit(index) {
                digitCount += 1
                index += 1
            }
        }
        guard digitCount > 0 else { return false }
        if isOne(of: "eE", index) {
            index += 1
            if isOne(of: "+-", index) { index += 1 }
            guard isDigit(index) else { return false }
            while isDigit(index) { index += 1 }
        }
        if isOne(of: "%", index) { index += 1 }
        return index == bytes.count
    }
}

/// The rows of a delimited text file.
///
/// Fields follow RFC 4180: one in double quotes can hold the delimiter, line breaks,
/// and `""` for a quote. Quotes anywhere else in a field are taken as written, and
/// blank lines are skipped.
nonisolated struct CSVTable {
    struct Row {
        /// The 1-based line of the text the row starts on.
        let line: Int
        let fields: [String]
    }

    /// The rows from the top of the file, up to the cell limit.
    private(set) var rows: [Row] = []
    /// How many rows the file has, including those past the limit.
    private(set) var rowCount = 0

    private static let quote = UInt16(UInt8(ascii: "\""))
    private static let lineFeed = UInt16(UInt8(ascii: "\n"))
    private static let carriageReturn = UInt16(UInt8(ascii: "\r"))
    private static let comma = UInt16(UInt8(ascii: ","))
    private static let semicolon = UInt16(UInt8(ascii: ";"))
    private static let tab = UInt16(UInt8(ascii: "\t"))

    /// `delimiter` is a UTF-16 code unit, or `nil` to detect it. Parsing stops keeping
    /// rows once they hold `maxCells` fields, but goes on counting them.
    init(parsing text: String, delimiter: UInt16?, maxCells: Int) {
        // In UTF-16, so lines are counted as the editor counts them. The delimiter,
        // quote and line breaks are each one unit, never part of another character.
        let units = Array(text.utf16)
        // Past a byte order mark, which would otherwise end up in the first field.
        var index = units.first == 0xFEFF ? 1 : 0
        let delimiter = delimiter ?? Self.detectDelimiter(in: units[index...])

        var fields: [String] = []
        var field: [UInt16] = []
        var isInQuotes = false
        // The field opened with a quote, so it counts as one even when it's empty.
        var isFieldQuoted = false
        var cellCount = 0
        var line = 1
        var rowLine = 1

        while index <= units.count {
            // The end of the text ends the last row, as a line break would.
            let isAtEnd = index == units.count
            let unit = isAtEnd ? Self.lineFeed : units[index]
            index += 1

            if isInQuotes, !isAtEnd {
                if unit != Self.quote {
                    field.append(unit)
                    // The quote that opened the field is before it, so there is a unit to look back at.
                    if Self.isLineBreak(unit), !(unit == Self.lineFeed && units[index - 2] == Self.carriageReturn) {
                        line += 1
                    }
                } else if index < units.count, units[index] == Self.quote {
                    field.append(Self.quote)
                    index += 1
                } else {
                    isInQuotes = false
                }
                continue
            }

            switch unit {
            case Self.quote where field.isEmpty && !isFieldQuoted:
                isInQuotes = true
                isFieldQuoted = true
            case delimiter:
                fields.append(String(decoding: field, as: UTF16.self))
                field.removeAll(keepingCapacity: true)
                isFieldQuoted = false
            case Self.lineFeed, Self.carriageReturn:
                if !fields.isEmpty || !field.isEmpty || isFieldQuoted {
                    fields.append(String(decoding: field, as: UTF16.self))
                    rowCount += 1
                    if cellCount < maxCells {
                        cellCount += fields.count
                        rows.append(Row(line: rowLine, fields: fields))
                    }
                    fields = []
                    field.removeAll(keepingCapacity: true)
                    isFieldQuoted = false
                }
                // CRLF is one line break.
                if unit == Self.carriageReturn, index < units.count, units[index] == Self.lineFeed {
                    index += 1
                }
                line += 1
                rowLine = line
            default:
                field.append(unit)
                // A Unicode line separator: a new line in the editor, but not a new row.
                if Self.isLineBreak(unit) { line += 1 }
            }
        }
    }

    /// The characters `NSString` (and so the editor) ends a line at.
    private static func isLineBreak(_ unit: UInt16) -> Bool {
        unit == lineFeed || unit == carriageReturn || unit == 0x85 || unit == 0x2028 || unit == 0x2029
    }

    /// A comma, unless the first row has more semicolons or tabs outside its quotes.
    private static func detectDelimiter(in units: ArraySlice<UInt16>) -> UInt16 {
        var commas = 0, semicolons = 0, tabs = 0
        var isInQuotes = false
        var isInRow = false
        for unit in units {
            if unit == quote {
                isInQuotes.toggle()
            } else if isInQuotes {
                continue
            } else if unit == lineFeed || unit == carriageReturn {
                // Blank lines before the first row don't count.
                if isInRow { break }
                continue
            } else if unit == comma {
                commas += 1
            } else if unit == semicolon {
                semicolons += 1
            } else if unit == tab {
                tabs += 1
            }
            isInRow = true
        }
        if semicolons > commas, semicolons >= tabs { return semicolon }
        if tabs > commas { return tab }
        return comma
    }
}
