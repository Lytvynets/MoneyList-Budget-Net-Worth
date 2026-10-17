import SwiftUI

struct MainShell: View {
    @Environment(Router.self) private var router
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            TodayScreen()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Router.Tab.today)
            LedgerScreen()
                .tabItem { Label("Ledger", systemImage: "book.closed") }
                .tag(Router.Tab.ledger)
            PlanScreen()
                .tabItem { Label("Plan", systemImage: "checklist") }
                .tag(Router.Tab.plan)
            WealthScreen()
                .tabItem { Label("Wealth", systemImage: "chart.xyaxis.line") }
                .tag(Router.Tab.wealth)
        }
        .overlay(alignment: .bottom) {
            if let toast = toasts.current {
                ToastBanner(toast: toast, onUndo: {
                    toast.undo?()
                    toasts.dismiss()
                }, onClose: {
                    toasts.dismiss()
                })
                .padding(.bottom, 72)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $router.composer) { request in
            ComposerSheet(request: request)
        }
        .sheet(isPresented: $router.showSettings) {
            SettingsScreen()
        }
    }
}

/// Floating "Write" button shown on screens without the quick line.
struct WriteButton: View {
    @Environment(Router.self) private var router
    @Environment(\.inkAccent) private var accent
    var kind: EntryKind = .expense

    var body: some View {
        Button {
            Haptic.tap()
            router.composer = ComposerRequest(kind: kind)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                Text("Write")
                    .font(Typeface.labelStrong)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(accent, in: Capsule())
            .shadow(color: accent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 18)
        .padding(.bottom, 14)
        .accessibilityLabel(Text("Write a new entry"))
    }
}
