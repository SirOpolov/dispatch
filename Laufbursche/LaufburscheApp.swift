import SwiftUI
import UIKit

let accent = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 1.00, green: 0.68, blue: 0.40, alpha: 1)
        : UIColor(red: 0.85, green: 0.40, blue: 0.13, alpha: 1)
})

@main
struct LaufburscheApp: App {
    @State private var store = Store()
    @AppStorage("theme") private var theme = 0

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(accent)
                .preferredColorScheme(theme == 1 ? .light : theme == 2 ? .dark : nil)
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var phase
    @AppStorage("interval") private var interval = 60
    @State private var adding = false

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                welcome
            } else {
                MailboxView()
            }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                AccountForm()
            }
        }
        .task(id: store.current?.id) {
            while !Task.isCancelled {
                await store.sync()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
        .onChange(of: phase) {
            if phase == .active {
                Task {
                    await store.sync()
                }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 64))
                .foregroundStyle(accent)
            Text("Laufbursche")
                .font(.largeTitle.bold())
            Button {
                adding = true
            } label: {
                Label("Konto hinzufügen", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
        }
    }
}
