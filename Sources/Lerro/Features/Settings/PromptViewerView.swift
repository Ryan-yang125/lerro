import AppKit
import SwiftUI
import LerroCore

extension AIPromptKind {
    /// Chinese UI key of the prompt name.
    var lerroTitle: String {
        switch self {
        case .dictate: "听写润色"
        case .translate: "翻译"
        case .dictionaryLearning: "自动学词"
        }
    }
}

private enum PromptViewMode: Hashable {
    case sections
    case fullText
}

/// Read-only viewer for the system prompt that Lerro sends to the model.
struct PromptViewerView: View {
    private static let sourceURL = URL(
        string: "https://github.com/Ryan-yang125/lerro/blob/main/Sources/LerroCore/Services/AIPromptDocument.swift"
    )

    let kind: AIPromptKind

    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var viewMode: PromptViewMode = .sections
    @State private var selectedSectionID: String?
    @State private var didCopy = false

    private let document: AIPromptDocument

    init(kind: AIPromptKind) {
        self.kind = kind
        let document = AIPromptDocument.document(for: kind)
        self.document = document
        _selectedSectionID = State(initialValue: document.sections.first?.id)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            detail
        }
        .navigationTitle(Text(verbatim: localized(kind.lerroTitle)))
        .navigationSubtitle(Text(verbatim: document.version))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("视图", selection: $viewMode) {
                    Text("分段").tag(PromptViewMode.sections)
                    Text("全文").tag(PromptViewMode.fullText)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .frame(minWidth: 720, minHeight: 480)
    }

    // MARK: Sidebar

    private var sidebarSelection: Binding<String?> {
        Binding {
            viewMode == .sections ? selectedSectionID : nil
        } set: { updated in
            guard let updated else { return }
            selectedSectionID = updated
            viewMode = .sections
        }
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            ForEach(document.sections) { section in
                HStack(spacing: 6) {
                    Text(verbatim: localized(section.title))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if section.isExamples {
                        Text(verbatim: "\(document.examples.count)")
                            .font(LerroFont.footnote.monospacedDigit())
                            .foregroundStyle(LerroTheme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(LerroTheme.fillContainerTough, in: Capsule())
                    }
                }
                .tag(section.id)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch viewMode {
        case .sections:
            if let section = document.sections.first(where: { $0.id == selectedSectionID }) {
                sectionDetail(section)
            } else {
                Color.clear
            }
        case .fullText:
            fullTextDetail
        }
    }

    private func sectionDetail(_ section: AIPromptSection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: localized(section.title))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(LerroTheme.text)
                    if !section.summary.isEmpty {
                        Text(verbatim: localized(section.summary))
                            .font(LerroFont.body)
                            .foregroundStyle(LerroTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if section.isExamples {
                    ForEach(document.examples) { example in
                        exampleCard(example)
                    }
                } else {
                    card {
                        Text(verbatim: section.text)
                            .font(LerroFont.body)
                            .lineSpacing(3)
                            .foregroundStyle(LerroTheme.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fullTextDetail: some View {
        ScrollView {
            card {
                Text(verbatim: document.fullText)
                    .font(.system(size: 12, design: .monospaced))
                    .lineSpacing(2)
                    .foregroundStyle(LerroTheme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return content()
            .padding(14)
            .background(LerroTheme.fillContainerThin, in: shape)
            .overlay { shape.strokeBorder(LerroTheme.thinBorder, lineWidth: 1) }
    }

    // MARK: Examples

    private func exampleCard(_ example: AIPromptExample) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "\(example.id). \(localized(example.title))")
                    .font(LerroFont.cardTitle)
                    .foregroundStyle(LerroTheme.text)

                exampleRow("说的话") {
                    Text(verbatim: example.said)
                        .foregroundStyle(LerroTheme.secondaryText)
                }

                if !example.context.isEmpty {
                    exampleRow("上下文") {
                        PromptChipFlow(spacing: 6) {
                            ForEach(Array(example.context.enumerated()), id: \.offset) { _, item in
                                chip(contextChipText(item))
                            }
                        }
                    }
                }

                if !example.fixes.isEmpty {
                    exampleRow("改词") {
                        PromptChipFlow(spacing: 6) {
                            ForEach(Array(example.fixes.enumerated()), id: \.offset) { _, fix in
                                chip("\(fix.recognized) → \(fix.corrected)")
                            }
                        }
                    }
                }

                exampleRow("应该写成") {
                    Text(verbatim: example.output)
                        .foregroundStyle(LerroTheme.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exampleRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: localized(title))
                .font(LerroFont.caption)
                .foregroundStyle(LerroTheme.secondaryText)
                .frame(width: 64, alignment: .leading)
            content()
                .font(LerroFont.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text)
            .font(LerroFont.caption)
            .foregroundStyle(LerroTheme.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(LerroTheme.fillContainerTough, in: Capsule())
    }

    private func contextChipText(_ item: AIPromptExampleContext) -> String {
        let value = item.label == "应用类型" ? localized(item.value) : item.value
        return LerroInterfaceLocalization.format(
            "%@：%@", locale: locale, arguments: localized(item.label), value
        )
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("在 GitHub 查看") {
                if let url = Self.sourceURL { openURL(url) }
            }
            .buttonStyle(LerroButtonStyle(.secondary))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(document.fullText, forType: .string)
                didCopy = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.5))
                    didCopy = false
                }
            } label: {
                Text(LocalizedStringKey(didCopy ? "已复制" : "复制全文"))
            }
            .buttonStyle(LerroButtonStyle(.secondary))

            Button("完成") { dismissWindow() }
                .buttonStyle(LerroButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

/// Left-aligned wrapping row of small views.
private struct PromptChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return arrange(maxWidth: maxWidth, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(maxWidth: bounds.width, subviews: subviews)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: usedWidth, height: y + rowHeight), origins)
    }
}
