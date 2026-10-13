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
@_silgen_name("NWHotspotUIRegressionCheck")
func checkHotspotUI() -> Int32
@_silgen_name("NWHotspotUIRegressionPresent")
func presentHotspot(_ phase: Int32) -> Int32
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
@_silgen_name("NWMainTabsUIRegressionUseLegacyTraits")
func useLegacyPadTraits()
@_silgen_name("NWPresentationDiagnosticsUIRegressionCheck")
func checkPresentationDiagnostics() -> Int32

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

// This opt-in fixture exercises the presentation transition omitted by the
// normal regression (which starts with TabView already on screen).  It never
// changes the original 21/47-check test path or runs its automatic snapshots.
private enum OnboardingTestMode: String {
    case disabled, immediate, late

    static func selected() -> OnboardingTestMode {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment["NW_UI_ONBOARDING_MODE"] ?? ""
        if arguments.contains("--ipad-onboarding-late") || environment == "late" { return .late }
        if arguments.contains("--ipad-onboarding-immediate") ||
            arguments.contains("--ipad-onboarding") || environment == "immediate" { return .immediate }
        return .disabled
    }
}

@main
struct UIRegressionApp: App {
    private let onboardingMode = OnboardingTestMode.selected()

    init() {
        setFixtureLanguage(ProcessInfo.processInfo.arguments.contains("es") ? 1 : 0)
        if ProcessInfo.processInfo.arguments.contains("legacy-traits") { useLegacyPadTraits() }
    }
    var body: some Scene {
        WindowGroup {
            if onboardingMode == .disabled {
                RegressionTabs()
            } else {
                OnboardingTransitionRegression(mode: onboardingMode)
            }
        }
    }
}

private struct OnboardingTransitionRegression: View {
    let mode: OnboardingTestMode
    @State private var mainVisible = false
    @State private var scheduled = false
    @State private var continued = false
    @State private var selection = 0
    @State private var startedAt = Date()
    @State private var before: [String: Any] = [:]
    @State private var continueAfterSeconds = 0.0

    private var transitionDelay: TimeInterval { mode == .late ? 16 : 2 }

    var body: some View {
        Group {
            if mainVisible {
                mainTabs
            } else {
                VStack(spacing: 24) {
                    Text("Welcome to NukeWireless").font(.title)
                    Text("Onboarding navigation regression fixture")
                    Button("CONTINUAR", action: continueToMain)
                        .accessibilityIdentifier("nw.fixture.continue")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("nw.fixture.welcome")
            }
        }
        .onAppear {
            guard !scheduled else { return }
            scheduled = true
            startedAt = Date()
            // Retain a real, tappable button; the automatic test invokes its
            // same action to make the run unattended and deterministic.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                before = presentationState()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + transitionDelay) {
                continueToMain()
            }
        }
    }

    private var mainTabs: some View {
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
            Text("Information fixture")
                .tabItem { Label("Info", systemImage: "info.circle") }.tag(2)
        }
        .accessibilityIdentifier("nw.fixture.main")
    }

    private func continueToMain() {
        guard !continued else { return }
        continued = true
        if before.isEmpty { before = presentationState() }
        continueAfterSeconds = Date().timeIntervalSince(startedAt)
        mainVisible = true
        // Allow SwiftUI to construct the tab controllers before inspecting
        // them.  A second sample catches a tab that appears later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let early = presentationState()
            write(["mode": mode.rawValue, "phase": "after-continue-early", "state": early],
                  "onboarding-\(mode.rawValue)-early.json")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            let after = presentationState()
            capture("onboarding-\(mode.rawValue)-main.png")
            let beforeHasTabs = before["tabs_found"] as? Bool ?? false
            let found = after["tabs_found"] as? Bool ?? false
            let nativeHosts = after["native_hosts"] as? Int ?? 0
            let barItems = after["presentation_items"] as? Int ?? 0
            let barAttached = after["presentation_attached"] as? Bool ?? false
            let selectedAttached = after["selected_attached"] as? Bool ?? false
            let selectedNonempty = after["selected_nonempty"] as? Bool ?? false
            let sizeClass = after["horizontal_size_class"] as? Int ?? 0
            let compactOnPad = UIDevice.current.userInterfaceIdiom != .pad ||
                sizeClass == UIUserInterfaceSizeClass.compact.rawValue
            let lateEnough = mode != .late || continueAfterSeconds > 12
            let passed = !beforeHasTabs && found && nativeHosts == 3 && barItems == 4 &&
                barAttached && selectedAttached && selectedNonempty && compactOnPad && lateEnough
            write(["fixture": "welcome-continue-three-tabs", "mode": mode.rawValue,
                   "transition_delay_seconds": transitionDelay,
                   "continue_after_seconds": continueAfterSeconds, "button_action_invoked": continued,
                   "late_after_diagnostics_window": lateEnough, "before": before, "after": after,
                   "passed": passed], "onboarding-\(mode.rawValue)-result.json")
        }
    }

    private func presentationState() -> [String: Any] {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.filter { !$0.isHidden }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return ["window_found": false, "tabs_found": false]
        }
        var examined = 0
        func findTabs(_ controller: UIViewController?, _ depth: Int) -> UITabBarController? {
            guard let controller, depth <= 12, examined < 64 else { return nil }
            examined += 1
            let tabs = (controller as? UITabBarController) ?? controller.tabBarController
            if let tabs, tabs.viewControllers?.count == 3 { return tabs }
            for child in controller.children {
                if let found = findTabs(child, depth + 1) { return found }
            }
            return nil
        }
        guard let tabs = findTabs(window.rootViewController, 0) else {
            return ["window_found": true, "tabs_found": false,
                    "window_width": Double(window.bounds.width),
                    "window_height": Double(window.bounds.height)]
        }
        let presentation = tabs.view.subviews.compactMap { $0 as? UITabBar }
            .first(where: { $0.accessibilityIdentifier == "nw.main.tabs" })
        let selected = tabs.selectedViewController?.viewIfLoaded
        return ["window_found": true, "tabs_found": true,
                "native_hosts": tabs.viewControllers?.count ?? 0,
                "selected_index": tabs.selectedIndex,
                "selected_attached": selected?.window != nil,
                "selected_nonempty": (selected?.bounds.width ?? 0) > 0 && (selected?.bounds.height ?? 0) > 0,
                "selected_width": Double(selected?.bounds.width ?? 0),
                "selected_height": Double(selected?.bounds.height ?? 0),
                "horizontal_size_class": tabs.traitCollection.horizontalSizeClass.rawValue,
                "presentation_items": presentation?.items?.count ?? 0,
                "presentation_attached": presentation?.window != nil,
                "presentation_hidden": presentation?.isHidden ?? true,
                "native_bar_attached": tabs.tabBar.window != nil,
                "window_width": Double(window.bounds.width),
                "window_height": Double(window.bounds.height)]
    }

    private func write(_ report: [String: Any], _ name: String) {
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: file, options: .atomic)
        }
    }

    private func capture(_ name: String) {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        try? image.pngData()?.write(to: file)
    }
}

struct RegressionTabs: View {
    @State private var selection = 0
    @State private var started = false
    @State private var results: [Int32] = []
    @State private var resumePhase = -1
    @State private var didBackground = false
    @State private var checkingResume = false
    @State private var rotationError = ""
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
            VStack {
                Text("Don't pirate!")
                Text("MidnightChips")
                Text("PINPAL")
            }
                .tabItem { Label("Info", systemImage: "info.circle") }.tag(2)
        }.onAppear {
            guard !started else { return }
            started = true
            if UIDevice.current.userInterfaceIdiom == .pad, #available(iOS 16.0, *) {
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: ProcessInfo.processInfo.arguments.contains("landscape") ? .landscapeRight : .portrait))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                results.append(checkUI(0))
                results.append(checkPresentationDiagnostics())
                self.recordStartupHierarchy()
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
                    writeReport(["results": results, "passed": results.allSatisfy { $0 == 0 } && results.count == 47,
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
    private func recordStartupHierarchy() {
        func describe(_ controller: UIViewController, depth: Int) -> [String: Any] {
            var result: [String: Any] = ["class": String(describing: type(of: controller))]
            result["horizontal_size_class"] = controller.traitCollection.horizontalSizeClass.rawValue
            if let parent = controller.parent, let traits = parent.overrideTraitCollection(forChild: controller) {
                result["parent_override_horizontal_size_class"] = traits.horizontalSizeClass.rawValue
            }
            if controller.isViewLoaded {
                let view = controller.view!
                result["frame"] = String(describing: view.frame)
                result["hidden"] = view.isHidden
                result["alpha"] = view.alpha
                result["attached"] = view.window != nil
                result["view_horizontal_size_class"] = view.traitCollection.horizontalSizeClass.rawValue
            }
            if let split = controller as? UISplitViewController {
                result["split_display_mode"] = split.displayMode.rawValue
                result["split_preferred_mode"] = split.preferredDisplayMode.rawValue
            }
            if depth < 12 { result["children"] = controller.children.map { describe($0, depth: depth + 1) } }
            return result
        }
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        let roots = windows.compactMap { $0.rootViewController }.map { describe($0, depth: 0) }
        writeReport(["roots": roots, "ipad": UIDevice.current.userInterfaceIdiom == .pad,
                     "window_sizes": windows.map { String(describing: $0.bounds.size) }], "startup-hierarchy.json")
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
                    writeReport(["results": results, "passed": results.allSatisfy { $0 == 0 } && results.count == 21], "ui-initial.json")
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
                    results.append(checkHotspotUI()); results.append(presentHotspot(0)); setDark(false)
                    captureHotspot(0)
                }
            }
        }
    }
    private func captureHotspot(_ phase: Int32) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if phase == 0 {
                snapshot("hotspot.png"); results.append(presentHotspot(1)); setDark(true); captureHotspot(1)
            } else {
                snapshot("hotspot-actions-dark.png"); results.append(presentHotspot(2))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    results.append(presentDiagnostics()); setDark(false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        snapshot("diagnostics.png"); setDark(true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            snapshot("diagnostics-dark.png")
                            let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                                .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })?.rootViewController
                            root?.dismiss(animated: false) { diagnosticNavigation(0) }
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
        let rotate = UIDevice.current.userInterfaceIdiom == .pad && ProcessInfo.processInfo.arguments.contains("rotate")
        let landscape = phase % 2 == 1
        rotationError = ""
        // Finish the selected-host transition before requesting geometry.
        // UIKit may decline a rotation during an unfinished containment change.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            if rotate, #available(iOS 16.0, *) {
                requestResumeRotation(landscape, 0)
            }
            recordResumeReady(phase, rotate, landscape, result, 0)
        }
    }
    @available(iOS 16.0, *)
    private func requestResumeRotation(_ landscape: Bool, _ attempt: Int) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.isKeyWindow { _ = orientationState(window.rootViewController) }
            // setNeedsUpdate... schedules an update; let UIKit process it before
            // evaluating geometry. A navigation transition can temporarily lock
            // the accepted mask to the current orientation despite public masks.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: landscape ? .landscapeRight : .portrait)) { error in
                    let failure = error as NSError
                    rotationError = "\(failure.domain):\(failure.code) \(failure.localizedDescription.prefix(600))"
                    if failure.domain == "UISceneErrorDomain", failure.code == 101, attempt < 3 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                            requestResumeRotation(landscape, attempt + 1)
                        }
                    }
                }
            }
        }
    }
    private func recordResumeReady(_ phase: Int, _ rotate: Bool, _ landscape: Bool, _ result: Int32, _ attempt: Int) {
        let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows }).first(where: { $0.isKeyWindow })
        let size = window?.bounds.size ?? .zero
        let correct = !rotate || ((size.width > size.height) == landscape)
        if !correct && attempt < 12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                recordResumeReady(phase, rotate, landscape, result, attempt + 1)
            }
            return
        }
        writeReport(["phase": phase, "tag": resumeTags[phase], "prepared": result == 0,
                     "rotation_requested": rotate, "orientation_correct": correct, "geometry_error": rotationError,
                     "window_width": size.width, "window_height": size.height,
                     "orientations": orientationState(window?.rootViewController),
                     "app_orientation_mask": window.map { UIApplication.shared.supportedInterfaceOrientations(for: $0).rawValue } ?? 0,
                     "pid": ProcessInfo.processInfo.processIdentifier], "resume-ready-\(phase).json")
    }
    private func orientationState(_ root: UIViewController?) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func collect(_ controller: UIViewController?, _ depth: Int) {
            guard let controller, depth < 8, result.count < 20 else { return }
            if #available(iOS 16.0, *) { controller.setNeedsUpdateOfSupportedInterfaceOrientations() }
            result.append(["class": String(describing: type(of: controller)),
                           "mask": controller.supportedInterfaceOrientations.rawValue,
                           "attached": controller.viewIfLoaded?.window != nil,
                           "transition_active": controller.transitionCoordinator != nil, "autorotate": controller.shouldAutorotate])
            for child in controller.children { collect(child, depth + 1) }
            collect(controller.presentedViewController, depth + 1)
        }
        collect(root, 0)
        return result
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
