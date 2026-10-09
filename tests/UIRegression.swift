import SwiftUI
import UIKit
import Combine
@_silgen_name("NWDiagnosticsUIRegressionCheck")
func checkDiagnosticsUI() -> Int32
@_silgen_name("NWDiagnosticsUIRegressionPresent")
func presentDiagnostics() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionCheck")
func checkBrowserUI() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionPresent")
func presentBrowser() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionSearch")
func searchBrowser() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionSelect")
func selectBrowser() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionMenu")
func checkBrowserMenu() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionRename")
func renameBrowser() -> Int32
@_silgen_name("NWDeviceBrowserUIRegressionRenameCheck")
func checkBrowserRename() -> Int32
@_silgen_name("NWEndDeviceActionsUITest")
func endBrowserFixture()
@_silgen_name("NWBluetoothUIRegressionCheck")
func checkBluetoothUI() -> Int32
@_silgen_name("NWBluetoothCatalogUIRegressionPresent")
func presentCatalog(_ platform: Int32) -> Int32
@_silgen_name("NWBluetoothUIRegressionCatalogState")
func catalogState(_ state: Int32) -> Int32
@_silgen_name("NWBluetoothCatalogUIRegressionSinglePresent")
func presentSingleEmission() -> Int32

@_silgen_name("NWBLEUIRegressionCheck")
func checkBLEUI() -> Int32

@_silgen_name("NWUIRegressionCheck")
func checkUI(_ phase: Int32) -> Int32
@_silgen_name("NWUIRegressionSetLanguage")
func setFixtureLanguage(_ spanish: Int32)
@_silgen_name("NWUIRegressionPrepareResume")
func prepareResumeTest(_ tag: Int32) -> Int32
@_silgen_name("NWUIRegressionCheckResume")
func checkResumeTest() -> Int32
@_silgen_name("NWUIRegressionDiagnosticNavigation")
func checkDiagnosticNavigation(_ phase: Int32) -> Int32

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
    @State private var resumePhase = -1
    @State private var didBackground = false
    @State private var checkingResume = false
    private let resumeTags: [Int32] = [0, 1, 3, 2]

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
                                results.append(checkDiagnosticsUI())
                                results.append(checkBLEUI())
                                results.append(checkBluetoothUI())
                                results.append(checkBrowserUI())
                                results.append(presentCatalog(0))
                                captureCatalog(0)
                            }
                        }
                    }
                }
            }
        }.onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIScene.didEnterBackgroundNotification))) { _ in
            if resumePhase >= 0 { didBackground = true }
        }.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIScene.didActivateNotification))) { _ in
            guard resumePhase >= 0, didBackground, !checkingResume else { return }
            checkingResume = true
            let phase = resumePhase
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let check = checkResumeTest()
                results.append(check)
                snapshot("resume-\(phase).png")
                writeReport(["phase": phase, "tag": resumeTags[phase], "result": check,
                             "background_seen": didBackground, "pid": ProcessInfo.processInfo.processIdentifier],
                            "resume-done-\(phase).json")
                if phase < 3 { prepareResume(phase + 1) }
                else {
                    resumePhase = -1
                    writeReport(["results": results, "passed": results.allSatisfy { $0 == 0 } && results.count == 42,
                                 "real_background_cycles": 4], "ui-regression.json")
                }
            }
        }
    }
    private func setDark(_ dark: Bool) {
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }) {
            window.overrideUserInterfaceStyle = dark ? .dark : .light
        }
    }
    private func captureCatalog(_ platform: Int32) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            snapshot("catalog-\(platform).png")
            if platform < 3 {
                results.append(presentCatalog(platform + 1))
                captureCatalog(platform + 1)
            } else {
                results.append(presentSingleEmission())
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    snapshot("catalog-single.png")
                    results.append(catalogState(0))
                    captureCatalogState(1)
                }
            }
        }
    }
    private func captureCatalogState(_ state: Int32) {
        results.append(catalogState(state))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if state > 0 {
                snapshot([1: "catalog-active.png", 2: "catalog-stopping.png", 3: "catalog-error.png"][state]!)
                captureCatalogState(state == 3 ? 0 : state + 1)
            } else {
                setDark(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    snapshot("catalog-dark.png")
                    writeReport(["results": results, "passed": results.allSatisfy { $0 == 0 } && results.count == 20], "ui-initial.json")
                    guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                        .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else { return }
                    root.dismiss(animated: false) {
                        let result = presentBrowser(); results.append(result)
                        captureBrowser(0, fixture: result == 0)
                    }
                }
            }
        }
    }
    private func captureBrowser(_ phase: Int, fixture: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if phase == 0 { results.append(searchBrowser()); captureBrowser(1, fixture: fixture) }
            else if phase == 1 { results.append(selectBrowser()); captureBrowser(2, fixture: fixture) }
            else if phase == 2 {
                results.append(checkBrowserMenu()); snapshot("browser-actions.png")
                results.append(renameBrowser()); captureBrowser(3, fixture: fixture)
            } else {
                results.append(checkBrowserRename()); snapshot("browser-rename.png")
                guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController else { return }
                root.dismiss(animated: false) {
                    if fixture { endBrowserFixture() }
                    results.append(presentDiagnostics())
                    setDark(false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        snapshot("diagnostics.png")
                        setDark(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            snapshot("diagnostics-dark.png")
                            root.dismiss(animated: false) { diagnosticNavigation(0) }
                        }
                    }
                }
            }
        }
    }
    private func diagnosticNavigation(_ phase: Int32) {
        results.append(checkDiagnosticNavigation(phase))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if phase == 2 { snapshot("diagnostic-emission.png") }
            if phase == 3 { snapshot("diagnostic-back.png") }
            if phase == 5 { snapshot("diagnostic-info.png") }
            if phase < 6 { diagnosticNavigation(phase + 1) }
            else { prepareResume(0) }
        }
    }
    private func prepareResume(_ phase: Int) {
        resumePhase = phase; didBackground = false; checkingResume = false
        setDark(phase < 2)
        let result = prepareResumeTest(resumeTags[phase])
        results.append(result)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            writeReport(["phase": phase, "tag": resumeTags[phase], "prepared": result == 0,
                         "pid": ProcessInfo.processInfo.processIdentifier], "resume-ready-\(phase).json")
        }
    }
    private func writeReport(_ report: [String: Any], _ name: String) {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
        try? JSONSerialization.data(withJSONObject: report).write(to: file)
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
