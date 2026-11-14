import SwiftUI
import UIKit
import UserNotifications

let defaultAccent = Color(UIColor { traits in
    traits.userInterfaceStyle == .dark
        ? UIColor(red: 1.00, green: 0.68, blue: 0.40, alpha: 1)
        : UIColor(red: 0.85, green: 0.40, blue: 0.13, alpha: 1)
})

func themeColor(_ hex: String) -> Color {
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard clean.count == 6, let value = Int(clean, radix: 16) else { return defaultAccent }
    return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
}

func hexString(_ color: Color) -> String {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let channel = { (value: CGFloat) in max(0, min(255, Int((value * 255).rounded()))) }
    return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
}

@main
struct LaufburscheApp: App {
    @State private var store = Store()
    @AppStorage("theme") private var theme = 0
    @AppStorage("accent") private var accent = ""

    var body: some Scene {
        let model = store
        WindowGroup {
            RootView()
                .environment(model)
                .tint(themeColor(accent))
                .preferredColorScheme(theme == 1 ? .light : theme == 2 ? .dark : nil)
        }
        .backgroundTask(.appRefresh(refreshTask)) {
            scheduleRefresh()
            await model.backgroundSync()
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
        .overlay(alignment: .bottom) {
            Toast()
        }
        .sensoryFeedback(.success, trigger: store.done)
        .sensoryFeedback(.error, trigger: store.failed)
        .sheet(isPresented: $adding) {
            NavigationStack {
                AccountForm()
            }
        }
        .task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        .task(id: store.scope) {
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
            if phase == .background {
                scheduleRefresh()
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
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

struct Toast: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            if let text = store.toast {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        store.toast = nil
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .task(id: store.done + store.failed) {
            do {
                try await Task.sleep(for: .seconds(2.5))
                store.toast = nil
            } catch {
                return
            }
        }
    }
}
