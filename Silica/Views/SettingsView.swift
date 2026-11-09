import SwiftUI

/// Settings (⌘,): editor font and indentation, what the editor shows, appearance,
/// and whether projects reopen their tabs. Changes apply to open editors at once.
struct SettingsView: View {
    @Bindable private var settings = EditorSettings.shared

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font", selection: fontFamily) {
                    Text("SF Mono (System)").tag("")
                    Divider()
                    ForEach(EditorSettings.monospacedFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }

                LabeledContent("Size") {
                    HStack(spacing: 8) {
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                        Stepper("Size", value: fontSize, in: EditorSettings.fontSizeRange, step: 1)
                            .labelsHidden()
                    }
                }

                Text(sample)
                    .font(Font(settings.editorFont(ofSize: settings.fontSize)))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05)))
            }

            Section {
                Picker("Tab width", selection: $settings.tabWidth) {
                    ForEach(EditorSettings.tabWidths, id: \.self) { width in
                        Text("\(width) spaces").tag(width)
                    }
                }
                Picker("Indent new files with", selection: $settings.indentsWithTabs) {
                    Text("Spaces").tag(false)
                    Text("Tabs").tag(true)
                }
            } header: {
                Text("Indentation")
            } footer: {
                Text("Files that are already indented keep their own style.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Editor") {
                Toggle("Show line numbers", isOn: $settings.showsLineNumbers)
                Toggle("Show indent guides", isOn: $settings.showsIndentGuides)
                Toggle("Wrap long lines", isOn: $settings.wrapsLines)
            }

            Section("Window") {
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(EditorSettings.Appearance.system)
                    Text("Light").tag(EditorSettings.Appearance.light)
                    Text("Dark").tag(EditorSettings.Appearance.dark)
                }
                .pickerStyle(.segmented)
                Toggle("Reopen a project’s tabs where you left them", isOn: $settings.restoresTabs)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sample: String {
        "func greet(_ name: String) -> String {\n" + String(repeating: " ", count: settings.tabWidth) + "return \"Hello, \\(name)!\"\n}"
    }

    /// "" stands for the system font in the picker.
    private var fontFamily: Binding<String> {
        Binding(
            get: { settings.fontFamily ?? "" },
            set: { settings.fontFamily = $0.isEmpty ? nil : $0 }
        )
    }

    private var fontSize: Binding<CGFloat> {
        Binding(
            get: { settings.fontSize },
            set: { settings.setFontSize($0) }
        )
    }
}
