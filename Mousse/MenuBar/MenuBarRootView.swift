import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @StateObject private var loginItem = LoginItemManager()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            highlightSection
            Divider()
            findSection
            Divider()
            generalSection
            if !model.failedHotkeys.isEmpty {
                hotkeyErrorBanner
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 400, alignment: .topLeading)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 19)
            Text("Mousse").font(.headline)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Mousse 종료")
        }
    }

    private var highlightSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("커서 강조")
            ActionRow(
                icon: "cursorarrow.rays",
                title: "커서에 원 표시",
                subtitle: model.isHighlightOn ? "켜짐 · 커서를 따라다녀요" : "꺼짐",
                subtitleColor: model.isHighlightOn ? .green : .secondary,
                hotkey: model.hotkey(for: .toggleHighlight)
            ) {
                Toggle("커서 강조", isOn: $model.isHighlightOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            SettingRow(label: "스타일") {
                Picker("스타일", selection: $settings.highlightStyle) {
                    ForEach(HighlightStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 120)
                Spacer()
            }
            SettingRow(label: "색상") {
                ColorSwatchPicker(selection: $settings.highlightColor)
            }
            SettingRow(label: "크기") {
                ValueSlider(value: $settings.highlightSize, range: AppSettings.sizeRange) {
                    "\(Int($0.rounded()))pt"
                }
            }
            SettingRow(label: "투명도") {
                ValueSlider(value: $settings.highlightOpacity, range: AppSettings.opacityRange) {
                    "\(Int(($0 * 100).rounded()))%"
                }
            }
        }
    }

    private var findSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("위치 찾기")
            ActionRow(
                icon: "scope",
                title: "커서 위치 보여주기",
                subtitle: "스포트라이트가 커서로 좁혀져요",
                hotkey: model.hotkey(for: .findCursor)
            ) {
                Button("보기") { model.findCursor() }
                    .controlSize(.small)
            }
            SettingRow(label: "배경") {
                Toggle("나머지 화면 어둡게", isOn: $settings.dimOnFind)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                Spacer()
            }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("일반")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("로그인 시 시작").font(.body)
                    Text("맥을 켜면 메뉴바에 자동으로 떠 있어요")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("로그인 시 시작", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            if let error = loginItem.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
        }
    }

    private var hotkeyErrorBanner: some View {
        let names = model.failedHotkeys
            .map { "\($0.label)(\(model.hotkey(for: $0).displayString))" }
            .joined(separator: ", ")
        return Label("\(names) 단축키를 등록하지 못했어요. 다른 앱이 쓰고 있을 수 있어요.",
                     systemImage: "exclamationmark.triangle.fill")
            .font(.caption).foregroundStyle(.orange).lineLimit(3)
    }

    private var footer: some View {
        HStack {
            Text("화면공유는 '전체 화면'으로 해야 효과가 보여요")
            Spacer()
            Text("v\(version)")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
}
