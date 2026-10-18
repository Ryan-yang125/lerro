import SwiftUI
import LerroCore

struct AppTonePickerSheet: View {
    let applications: [ApplicationDescriptor]
    let dictationCounts: [String: Int]
    let excludedBundleIdentifiers: Set<String>
    let select: (ApplicationDescriptor) -> Void
    let cancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("选择应用")
                    .font(LerroFont.pageTitle)
                Spacer()
                Button("取消", action: cancel)
                    .buttonStyle(LerroButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction)
            }

            TextField("搜索应用", text: $searchText)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.applications) { application in
                            Button {
                                select(application)
                            } label: {
                                HStack(spacing: 10) {
                                    LerroAppIcon(
                                        bundleIdentifier: application.bundleIdentifier,
                                        name: application.name,
                                        size: 28
                                    )
                                    Text(verbatim: application.name)
                                        .font(LerroFont.bodyEmphasis)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: application.name))
                            .help(application.bundleIdentifier)
                        }
                    } header: {
                        Text(title(for: section.kind))
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if sections.isEmpty {
                    LerroEmptyState(title: "没有匹配的应用", hint: nil)
                }
            }
        }
        .padding(20)
        .frame(width: 480, height: 480)
        .background(LerroTheme.main)
    }

    private var sections: [ApplicationPickerSection] {
        ApplicationPickerGrouping.sections(
            applications: applications,
            dictationCounts: dictationCounts,
            excludedBundleIdentifiers: excludedBundleIdentifiers,
            query: searchText
        )
    }

    private func title(for kind: ApplicationPickerSectionKind) -> LocalizedStringKey {
        switch kind {
        case .frequent: "常用"
        case .running: "正在运行"
        case .installed: "全部应用"
        }
    }
}
