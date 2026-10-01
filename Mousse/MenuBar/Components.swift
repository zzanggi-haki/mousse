import SwiftUI

/// CAPTION · SEMIBOLD · UPPERCASE · secondary (design system §6.2).
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption).fontWeight(.semibold)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// A keycap-style chip showing a global shortcut, e.g. "⌃⌥H".
struct ShortcutBadge: View {
    let hotkey: Hotkey

    var body: some View {
        Text(hotkey.displayString)
            .font(.caption.monospaced())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
            .help("단축키 \(hotkey.displayString)")
    }
}

/// Icon · title/subtitle · shortcut · trailing control (design system §6.3).
struct ActionRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var subtitleColor: Color = .secondary
    let hotkey: Hotkey
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle).font(.caption).foregroundStyle(subtitleColor)
            }
            Spacer()
            ShortcutBadge(hotkey: hotkey)
            trailing()
        }
        .padding(.vertical, 4)
    }
}

/// A labelled settings line: fixed-width label column, control to the right.
struct SettingRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            content()
        }
    }
}

/// A keycap-style chip for a single key, e.g. "R" or "Esc".
struct KeyCap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.caption.monospaced())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(minWidth: 30)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.secondary)
    }
}

/// A slider with its current value shown at a fixed width so the row doesn't jitter.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text(format(value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// Preset color dots. Swatches instead of a ColorPicker keep every color choice to the
/// same small, presentation-friendly palette.
struct ColorSwatchPicker: View {
    @Binding var selection: PaletteColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PaletteColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(selection == color ? 0.85 : 0), lineWidth: 2)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
                .help(color.label)
            }
            Spacer()
        }
    }
}
