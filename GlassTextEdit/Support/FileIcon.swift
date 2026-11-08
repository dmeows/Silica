import SwiftUI

/// SF Symbol + tint for a file, loosely matching editor file-icon themes.
struct FileIcon: View {
    let url: URL
    var isDirectory = false
    var isExpanded = false

    var body: some View {
        let (symbol, color) = Self.style(for: url, isDirectory: isDirectory, isExpanded: isExpanded)
        Image(systemName: symbol)
            .symbolVariant(isDirectory ? .fill : .none)
            .foregroundStyle(color)
            .frame(width: 16)
    }

    static func style(for url: URL, isDirectory: Bool, isExpanded: Bool) -> (String, Color) {
        if isDirectory {
            return (isExpanded ? "folder" : "folder", .accentColor)
        }
        let name = url.lastPathComponent.lowercased()
        switch name {
        case "package.swift": return ("swift", .orange)
        case "dockerfile": return ("shippingbox", .blue)
        case "makefile": return ("hammer", .gray)
        case "license", "license.md", "license.txt": return ("checkmark.seal", .yellow)
        case ".gitignore", ".gitattributes": return ("arrow.triangle.branch", .orange)
        default: break
        }
        switch url.pathExtension.lowercased() {
        case "swift": return ("swift", .orange)
        case "js", "mjs", "cjs", "jsx": return ("curlybraces", .yellow)
        case "ts", "tsx": return ("curlybraces", .blue)
        case "json", "jsonc": return ("curlybraces.square", .green)
        case "md", "markdown", "mdx": return ("text.alignleft", .cyan)
        case "html", "htm", "xml", "svg", "vue": return ("chevron.left.forwardslash.chevron.right", .orange)
        case "css", "scss", "sass", "less": return ("paintbrush", .purple)
        case "py": return ("chevron.left.forwardslash.chevron.right", .teal)
        case "rb", "rs", "go", "java", "kt", "c", "h", "m", "mm", "cpp", "hpp", "cs", "php":
            return ("chevron.left.forwardslash.chevron.right", .indigo)
        case "sh", "zsh", "bash", "fish": return ("terminal", .green)
        case "yml", "yaml", "toml", "ini", "plist", "xcconfig", "env": return ("gearshape", .gray)
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "ico", "icns": return ("photo", .mint)
        case "pdf": return ("doc.richtext", .red)
        case "zip", "gz", "tar", "rar", "7z": return ("archivebox", .brown)
        case "lock", "resolved": return ("lock", .gray)
        case "txt", "log": return ("doc.plaintext", .secondary)
        default: return ("doc", .secondary)
        }
    }
}
