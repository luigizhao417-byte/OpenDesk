import SwiftUI

@main
struct OpenDeskApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, appState.appLocale)
                .frame(minWidth: 1180, minHeight: 780)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environment(\.locale, appState.appLocale)
                .frame(width: 620, height: 760)
                .preferredColorScheme(.dark)
        }
    }
}
