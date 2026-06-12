import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 8) {
                Text("HTMLViewer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                Text("M1: app skeleton")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
