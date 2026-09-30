import SwiftUI

@_silgen_name("NWUIRegressionCheck")
func checkUI(_ phase: Int32) -> Int32

@main
struct UIRegressionApp: App {
    var body: some Scene {
        WindowGroup { RegressionTabs() }
    }
}

struct RegressionTabs: View {
    @State private var selection = 0
    @State private var started = false
    @State private var results: [Int32] = []

    var body: some View {
        TabView(selection: $selection) {
            NavigationView {
                Text("WiFi fixture").navigationTitle("Harpy")
            }.tabItem { Label("WiFi", systemImage: "wifi") }.tag(0)
            Text("Hotspot fixture")
                .tabItem { Label("Hotspot", systemImage: "link") }.tag(1)
            Text("Legacy banner fixture")
                .tabItem { Label("Info", systemImage: "info.circle") }.tag(2)
        }.onAppear {
            guard !started else { return }
            started = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                results.append(checkUI(0))
                selection = 2
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    results.append(checkUI(1))
                    selection = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        results.append(checkUI(2))
                        let report: [String: Any] = ["results": results, "passed": results == [0, 0, 0]]
                        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            .appendingPathComponent("ui-regression.json")
                        try? JSONSerialization.data(withJSONObject: report).write(to: file)
                    }
                }
            }
        }
    }
}
