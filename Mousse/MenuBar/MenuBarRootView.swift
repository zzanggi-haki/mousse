import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            toolsSection
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
                .frame(width: 25, height: 16)
            Text("Mousse").font(.headline)
            Spacer()
            Button {
                model.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("설정 (모양·단축키·로그인 시 시작)")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Mousse 종료")
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("도구")
            ActionRow(
                icon: "cursorarrow.rays",
                title: "커서 강조",
                subtitle: model.isHighlightOn ? "켜짐 · 커서를 따라다녀요" : "꺼짐",
                subtitleColor: model.isHighlightOn ? .green : .secondary,
                hotkey: model.hotkey(for: .toggleHighlight)
            ) {
                Toggle("커서 강조", isOn: $model.isHighlightOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            ActionRow(
                icon: "scope",
                title: "위치 찾기",
                subtitle: "스포트라이트가 커서로 좁혀져요",
                hotkey: model.hotkey(for: .findCursor)
            ) {
                Button("보기") { model.findCursor() }
                    .controlSize(.small)
            }
            ActionRow(
                icon: "pencil.and.outline",
                title: "그리기",
                subtitle: drawingSubtitle,
                subtitleColor: model.isDrawing ? .green : .secondary,
                hotkey: model.hotkey(for: .toggleDrawing)
            ) {
                Button(model.isDrawing ? "끝내기" : "시작") { model.toggleDrawing() }
                    .controlSize(.small)
            }
        }
    }

    private var drawingSubtitle: String {
        if model.isDrawing { return "그리는 중 · Esc로 끝내기" }
        let keys = DrawTool.allCases.map { "\($0.key) \($0.label)" } + ["Esc 끝"]
        return keys.joined(separator: " · ")
    }

    private var hotkeyErrorBanner: some View {
        let names = model.failedHotkeys
            .map { "\($0.label)(\(model.hotkey(for: $0).displayString))" }
            .joined(separator: ", ")
        return Label("\(names) 단축키를 등록하지 못했어요. 설정에서 다른 조합으로 바꿔 보세요.",
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
