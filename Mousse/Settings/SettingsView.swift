import SwiftUI

/// Content of the settings window; the toolbar above it picks the tab.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var recorder: HotkeyRecorder

    var body: some View {
        Group {
            switch selection.tab {
            case .cursor: CursorSettings(settings: settings)
            case .drawing: DrawingSettings(settings: settings)
            case .shortcuts: ShortcutSettings(model: model, settings: settings, recorder: recorder)
            case .general: GeneralSettings()
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 커서

private struct CursorSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("커서 강조")
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
                Text("바꾸면 커서 위치에 잠깐 미리 보여줘요")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("위치 찾기")
                SettingRow(label: "배경") {
                    Toggle("나머지 화면 어둡게", isOn: $settings.dimOnFind)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - 그리기

private struct DrawingSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DrawingPreview(style: settings.drawingStyle)
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("선 · 펜")
                SettingRow(label: "색상") {
                    ColorSwatchPicker(selection: $settings.drawLineColor)
                }
                SettingRow(label: "두께") {
                    ValueSlider(value: $settings.drawLineWidth, range: AppSettings.lineWidthRange) {
                        "\(Int($0.rounded()))pt"
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("사각형 채우기")
                SettingRow(label: "색상") {
                    ColorSwatchPicker(selection: $settings.drawFillColor)
                }
                SettingRow(label: "불투명도") {
                    ValueSlider(value: $settings.drawFillOpacity, range: AppSettings.fillOpacityRange) {
                        $0 < 0.005 ? "없음" : "\(Int(($0 * 100).rounded()))%"
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("그리고 나서 자동으로 사라지기").font(.body)
                        Text(settings.drawAutoFade
                             ? "다 그린 뒤 정해진 시간이 지나면 하나씩 페이드아웃돼요"
                             : "Esc로 그리기 모드를 끝낼 때까지 남아 있어요")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("자동으로 사라지기", isOn: $settings.drawAutoFade)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                SettingRow(label: "시간") {
                    ValueSlider(value: $settings.drawFadeDelay, range: AppSettings.fadeDelayRange) {
                        "\(Int($0.rounded()))초"
                    }
                }
                .disabled(!settings.drawAutoFade)
            }
            Divider()
            DrawingKeysLegend()
        }
    }
}

/// A small sample of a rectangle and a pen stroke in the current drawing style.
private struct DrawingPreview: View {
    let style: DrawingStyle

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 28, y: 20, width: size.width * 0.38, height: size.height - 40)
            let radius = min(6, rect.width / 2, rect.height / 2)
            let box = Path(roundedRect: rect, cornerRadius: radius)
            let stroke = StrokeStyle(lineWidth: style.lineWidth, lineCap: .round, lineJoin: .round)
            if let fill = style.fillColor {
                context.fill(box, with: .color(Color(nsColor: fill)))
            }
            context.stroke(box, with: .color(Color(nsColor: style.lineColor)), style: stroke)

            let start = size.width * 0.52
            let span = size.width * 0.4
            let points = (0...40).map { i -> CGPoint in
                let t = CGFloat(i) / 40
                return CGPoint(x: start + span * t, y: size.height / 2 + 14 * sin(t * .pi * 3))
            }
            let pen = Path(DrawingCanvas.smoothPath(through: points))
            context.stroke(pen, with: .color(Color(nsColor: style.lineColor)), style: stroke)
        }
        .frame(height: 96)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// The single-key commands available inside drawing mode.
private struct DrawingKeysLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("그리기 모드 안에서")
            ForEach(DrawTool.allCases) { tool in
                legendRow(key: tool.key, text: "\(tool.label)으로 바꾸기")
            }
            legendRow(key: "Esc", text: "그리기 모드 끝내기 — 그린 것도 모두 지워져요")
        }
    }

    private func legendRow(key: String, text: String) -> some View {
        HStack(spacing: 10) {
            KeyCap(key)
            Text(text).font(.callout)
        }
    }
}

// MARK: - 단축키

private struct ShortcutSettings: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var recorder: HotkeyRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("전역 단축키")
                ForEach(HotkeyAction.allCases) { action in
                    HStack {
                        Text(action.label).font(.body)
                        Spacer()
                        recorderButton(for: action)
                    }
                }
                if let message = recorder.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(3)
                } else if !model.failedHotkeys.isEmpty {
                    Label(
                        model.failedHotkeys.map { "\($0.label)(\(model.hotkey(for: $0).displayString))" }
                            .joined(separator: ", ") + " 단축키를 등록하지 못했어요. 다른 앱이 쓰고 있을 수 있어요.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
                }
                HStack(alignment: .top) {
                    Text("버튼을 누르고 새 조합을 입력하세요 · Esc 취소\n⌃·⌥·⌘ 중 하나는 같이 눌러야 해요")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("기본값으로") { recorder.resetAll() }
                        .controlSize(.small)
                        .disabled(settings.customHotkeys.isEmpty)
                }
            }
            Divider()
            DrawingKeysLegend()
        }
    }

    @ViewBuilder
    private func recorderButton(for action: HotkeyAction) -> some View {
        let isRecording = recorder.recording == action
        let title = isRecording
            ? (recorder.heldModifiers == 0 ? "입력하세요…" : Hotkey.modifierSymbols(recorder.heldModifiers) + "…")
            : model.hotkey(for: action).displayString
        let button = Button {
            isRecording ? recorder.stop() : recorder.start(action)
        } label: {
            Text(title)
                .font(.callout.monospaced())
                .frame(minWidth: 96)
        }
        .help(isRecording ? "Esc로 취소" : "눌러서 단축키 바꾸기")

        if isRecording {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

// MARK: - 일반

private struct GeneralSettings: View {
    @StateObject private var loginItem = LoginItemManager()

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Divider()
            HStack {
                Text("효과는 화면공유를 '전체 화면'으로 해야 송출돼요")
                Spacer()
                Text("Mousse v\(version)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }
}
