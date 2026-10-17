import SwiftUI

/// A note from the developer, set in Remote Config without an app update:
/// "a new version is available" (`latest_version`) or a short announcement
/// (`notice_text_en` / `notice_text_uk`, optional `notice_url`).
/// Each message can be dismissed and then stays hidden.
struct NoticeCard: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.inkAccent) private var accent
    @AppStorage(AppConfig.Keys.noticeDismissed) private var dismissed = ""

    private struct Notice {
        let id: String
        let kind: String
        let symbol: String
        let text: String
        let action: String?
        let url: URL?
    }

    var body: some View {
        if let notice = current, notice.id != dismissed {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: notice.text)
                        .font(Typeface.label)
                        .foregroundStyle(Ink.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let action = notice.action, let url = notice.url {
                        Button {
                            Telemetry.event("notice_tap", ["notice": notice.kind])
                            openURL(url)
                        } label: {
                            Text(verbatim: action)
                                .font(Typeface.labelStrong)
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { dismissed = notice.id }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Ink.faint)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
            .paperCard()
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var current: Notice? {
        let dials = RemoteDials.shared
        let installed = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let latest = dials.string(.latestVersion)
        if !latest.isEmpty, installed.compare(latest, options: .numeric) == .orderedAscending {
            return Notice(
                id: "update-" + latest,
                kind: "update",
                symbol: "arrow.down.circle",
                text: String(localized: "A new version of Money List is available."),
                action: String(localized: "Update"),
                url: AppConfig.appStorePage
            )
        }

        let ukrainian = Bundle.main.preferredLocalizations.first?.hasPrefix("uk") == true
        let preferred = ukrainian ? dials.string(.noticeTextUK) : dials.string(.noticeTextEN)
        let text = preferred.isEmpty ? dials.string(.noticeTextEN) : preferred
        guard !text.isEmpty else { return nil }
        let link = URL(string: dials.string(.noticeURL)).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
        return Notice(
            id: "notice-" + text,
            kind: "message",
            symbol: "megaphone",
            text: text,
            action: link == nil ? nil : String(localized: "Open"),
            url: link
        )
    }
}
