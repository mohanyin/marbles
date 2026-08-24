import SwiftUI

/// Stub until W7. Exists so Settings is a real scene and the menu item has somewhere to go.
struct PreferencesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preferences")
                .font(.title2)
            Text("Reduced motion, completion sound, and hook repair land in later workstreams.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }
}
