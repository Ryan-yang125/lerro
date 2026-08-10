import SwiftUI

struct RecentDeliveryCorrectionView: View {
    let session: AppSession
    let receipt: AppSession.DeliveryReceiptPresentation
    @State private var correctedText: String
    @State private var phrase = ""
    @State private var replacement = ""
    @State private var isSaving = false

    init(session: AppSession, receipt: AppSession.DeliveryReceiptPresentation) {
        self.session = session
        self.receipt = receipt
        _correctedText = State(initialValue: receipt.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("修正并学习")
                    .lerroTypography(.title)
                Spacer()
                Text(verbatim: receipt.applicationName)
                    .lerroTypography(.caption)
                    .foregroundStyle(LerroTheme.metadataText)
            }

            TextEditor(text: $correctedText)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 170)
                .background(LerroTheme.main)
                .clipShape(RoundedRectangle(
                    cornerRadius: LerroTheme.controlRadius,
                    style: .continuous
                ))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: LerroTheme.controlRadius,
                        style: .continuous
                    )
                    .stroke(LerroTheme.focusBorder, lineWidth: 1)
                }

            HStack(spacing: 10) {
                TextField("识别成了", text: $phrase)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundStyle(LerroTheme.secondaryText)
                TextField("以后写成", text: $replacement)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("取消") { session.cancelRecentDeliveryCorrection() }
                    .buttonStyle(LerroPillButtonStyle())
                    .disabled(isSaving)
                Button("替换并保存") {
                    isSaving = true
                    Task { @MainActor in
                        _ = await session.applyRecentDeliveryCorrection(
                            receiptID: receipt.id,
                            correctedText: correctedText,
                            phrase: phrase,
                            replacement: replacement
                        )
                        isSaving = false
                    }
                }
                .buttonStyle(LerroPillButtonStyle(prominent: true))
                .disabled(
                    correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isSaving
                )
            }
        }
        .padding(24)
        .frame(width: 800, height: 410)
        .background(LerroTheme.main)
    }
}
