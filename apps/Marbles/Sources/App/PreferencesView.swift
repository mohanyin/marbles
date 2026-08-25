import SwiftUI

struct PreferencesView: View {
    @State private var reducedMotion = PrefsStore.shared.values.reducedMotion
    @State private var completionSound = PrefsStore.shared.values.completionSound
    @State private var satellites = PrefsStore.shared.values.satellites
    @State private var launchAtLogin = PrefsStore.shared.values.launchAtLogin

    var body: some View {
        Form {
            Toggle("Reduce motion", isOn: $reducedMotion)
                .onChange(of: reducedMotion) { _, value in
                    PrefsStore.shared.update { $0.reducedMotion = value }
                }
            Text("Follows System Settings → Reduce Motion as well. Layout snaps instead of springs.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Completion sound", isOn: $completionSound)
                .onChange(of: completionSound) { _, value in
                    PrefsStore.shared.update { $0.completionSound = value }
                }
            Toggle("Show subagent satellites", isOn: $satellites)
                .onChange(of: satellites) { _, value in
                    PrefsStore.shared.update { $0.satellites = value }
                }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    PrefsStore.shared.update { $0.launchAtLogin = value }
                    LoginItem.apply(value)
                }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .onAppear {
            let prefs = PrefsStore.shared.values
            reducedMotion = prefs.reducedMotion
            completionSound = prefs.completionSound
            satellites = prefs.satellites
            launchAtLogin = prefs.launchAtLogin
        }
    }
}
