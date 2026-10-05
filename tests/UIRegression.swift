import SwiftUI
import UIKit
@_silgen_name("NWBluetoothUIRegressionCheck")
func checkBluetoothUI() -> Int32

@_silgen_name("NWBLEUIRegressionCheck")
func checkBLEUI() -> Int32

@_silgen_name("NWUIRegressionCheck")
func checkUI(_ phase: Int32) -> Int32
@_silgen_name("NWUIRegressionSetLanguage")
func setFixtureLanguage(_ spanish: Int32)

@main
struct UIRegressionApp: App {
    init() { setFixtureLanguage(ProcessInfo.processInfo.arguments.contains("es") ? 1 : 0) }
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
                VStack {
                    Text("No devices found!")
                    Text("No WiFi Available")
                    Text("Unknown MAC Address")
                }.navigationTitle("Harpy")
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
                snapshot("wifi.png")
                selection = 2
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    results.append(checkUI(1))
                    snapshot("info.png")
                    results.append(checkUI(3))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        results.append(checkUI(5))
                        snapshot("bluetooth.png")
                        setDark(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            snapshot("bluetooth-dark.png")
                            setDark(false)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                results.append(checkUI(4))
                                results.append(checkUI(2))
                                results.append(checkBLEUI())
                                results.append(checkBluetoothUI())
                                let report: [String: Any] = ["results": results, "passed": results == [0, 0, 0, 0, 0, 0, 0, 0]]
                                let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                                    .appendingPathComponent("ui-regression.json")
                                try? JSONSerialization.data(withJSONObject: report).write(to: file)
                            }
                        }
                    }
                }
            }
        }
    }
    private func setDark(_ dark: Bool) {
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }) {
            window.overrideUserInterfaceStyle = dark ? .dark : .light
        }
    }
    private func snapshot(_ name: String) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? image.pngData()?.write(to: file)
    }
}
