import SwiftUI
import UIKit

@main
@MainActor
struct RideConsoleApp: App {
    @StateObject private var wheel = WheelConnection()
    @StateObject private var library = RideLibrary()
    @StateObject private var camera = CameraModel()
    @StateObject private var route = RouteRecorder()
    @StateObject private var store = ConsoleStore()
    @StateObject private var samples = ConsoleSamples()

    var body: some Scene {
        WindowGroup {
            ConsoleRoot(wheel: wheel, library: library, camera: camera, route: route, store: store, samples: samples)
                .preferredColorScheme(.dark)
                .tint(RideColors.accent)
        }
    }
}

enum RideColors {
    static let background = rgb(0x10151A)
    static let surface = rgb(0x1A242C)
    static let accent = rgb(0x79E5BF)
    static let instrument = rgb(0xEDF3F6)
    static let muted = rgb(0xA4B4C0)
    static let line = Color.white.opacity(0.12)

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}

@MainActor
private struct ConsoleRoot: View {
    private enum Page { case instruments, garage, rides, settings }
    private enum Cover: String, Identifiable {
        case camera, wheel, route
        var id: Self { self }
    }

    @ObservedObject var wheel: WheelConnection
    @ObservedObject var library: RideLibrary
    @ObservedObject var camera: CameraModel
    @ObservedObject var route: RouteRecorder
    @ObservedObject var store: ConsoleStore
    @ObservedObject var samples: ConsoleSamples
    @Environment(\.scenePhase) private var phase
    @AppStorage("keepDashboardAwake") private var keepDashboardAwake = true
    @State private var page = Page.instruments
    @State private var cover: Cover?
    @State private var events = [RideEvent]()
    @State private var ready = false

    var body: some View {
        tabs
            .task { connectObservers() }
            .fullScreenCover(item: $cover, content: coverContent)
            .onChange(of: phase) { _, value in phaseChanged(value) }
            .onReceive(wheel.$telemetry) { updateCamera($0) }
            .onChange(of: wheel.showingLastReading) { _, _ in updateCamera(wheel.telemetry) }
            .onChange(of: wheel.strobe) { _, _ in updateIdleTimer() }
            .onChange(of: camera.recording) { _, _ in updateIdleTimer() }
            .onChange(of: page) { _, _ in updateIdleTimer() }
            .onChange(of: cover) { _, _ in updateIdleTimer() }
            .onChange(of: keepDashboardAwake) { _, _ in updateIdleTimer() }
            .onChange(of: wheel.status) { _, value in addEvent(value) }
            .onChange(of: wheel.commandStatus) { _, value in if let value { addEvent(value) } }
            .onChange(of: route.started) { _, value in
                addEvent(value == nil ? "Запись GPS завершена" : "Запись GPS началась")
            }
    }

    private var tabs: some View {
        TabView(selection: $page) {
            ConsoleDashboard(store: store, wheel: wheel, route: route, samples: samples,
                             camera: { cover = .camera }, openGarage: { page = .garage })
                .tabItem { Label("Приборы", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(Page.instruments)
            GarageView(wheel: wheel, store: store, openSettings: { cover = .wheel },
                       openDashboard: { page = .instruments })
                .tabItem { Label("Гараж", systemImage: "circle.circle") }
                .tag(Page.garage)
            LibraryView(library: library, camera: camera) { cover = .route }
                .tabItem { Label("Поездки", systemImage: "map") }
                .tag(Page.rides)
            ConsoleSettings(store: store, wheel: wheel, library: library, events: events)
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
                .tag(Page.settings)
        }
        .background(RideColors.background.ignoresSafeArea())
    }

    private func connectObservers() {
        guard !ready else { return }
        ready = true

        wheel.onSample = { [weak library, weak route, weak samples, weak store] frame, demo, time in
            if !demo { route?.append(frame, at: time) }
            let fix = demo ? nil : route?.fixForLog(at: time)
            library?.append(frame, demo: demo, time: time, fix: fix)
            samples?.receive(ConsoleMetric.readings(frame, fix: fix), rules: store?.settings.rules ?? [], live: !demo)
        }
        wheel.onTelemetryLost = { [weak route, weak samples] time in
            route?.wheelLost(at: time)
            samples?.clearAlerts()
        }
        wheel.onSourceEnded = { [weak library] in library?.stopLog() }
        wheel.onWheelReady = { [weak store, weak route, weak wheel] entry in
            guard let store else { return }
            store.seenWheel(entry)
            if store.settings.automaticRide { route?.start(seed: wheel?.telemetry) }
        }
        wheel.onUnexpectedDisconnect = { [weak wheel, weak store] id in
            guard let store, store.settings.autoConnect, let wheel else { return }
            if UIApplication.shared.applicationState == .active { wheel.scan(for: id) }
        }
        route.onFileChange = { [weak library] url in library?.setActiveRoute(url) }
        camera.onVideoSaved = { [weak library] in library?.refresh() }
        updateCamera(wheel.telemetry)
        updateIdleTimer()

        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            wheel.setDemo(true)
            return
        }
        #endif
        if store.settings.autoConnect, let id = store.settings.lastWheel {
            if let entry = store.settings.wheels.first(where: { $0.id == id }) {
                wheel.preferredFamily = WheelFamily(rawValue: entry.protocolKey) ?? .automatic
            }
            wheel.scan(for: id)
        }
    }

    @ViewBuilder private func coverContent(_ item: Cover) -> some View {
        switch item {
        case .camera:
            RideCameraView(wheel: wheel, camera: camera)
                .onAppear { if phase == .active { camera.open() } }
                .onDisappear { camera.close() }
        case .wheel:
            WheelControls(wheel: wheel)
        case .route:
            LiveRouteView(recorder: route, wheel: wheel)
        }
    }

    private func phaseChanged(_ value: ScenePhase) {
        if value != .active { wheel.stopStrobe() }
        if value == .background {
            camera.close()
            wheel.stopScan()
        }
        if value == .active, cover == .camera { camera.open() }
        updateIdleTimer()
    }

    private func addEvent(_ message: String) {
        events.insert(RideEvent(message: message), at: 0)
        if events.count > 80 { events.removeLast() }
    }

    private func updateCamera(_ frame: Telemetry) {
        camera.update(.init(telemetry: frame, demo: wheel.demo, stale: wheel.showingLastReading, model: wheel.modelName))
    }

    private func updateIdleTimer() {
        let dashboardIsVisible = keepDashboardAwake && page == .instruments && cover == nil
        UIApplication.shared.isIdleTimerDisabled = phase == .active &&
            (dashboardIsVisible || camera.recording != .idle || wheel.strobe)
    }
}

struct RideScreen<Content: View>: View {
    let title: String
    var showsClose = false
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .frame(maxWidth: 650)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
            }
            .background(RideColors.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Назад", systemImage: "chevron.left") { dismiss() }
                    }
                }
            }
        }
    }
}

struct RidePanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(RideColors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16).strokeBorder(RideColors.line)
                    .allowsHitTesting(false)
            }
    }
}
