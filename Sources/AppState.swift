import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selection: AppSection = .sensors
    @Published private(set) var controllers: [ControllerState] = []
    @Published private(set) var activeControllerIDs: [ControllerRole: UUID] = [:]
    @Published var connectedControllers: Set<UUID> = []  // Track connected controllers
    @Published var logs: [LogEntry] = []
    @Published var weather: WeatherModel = WeatherModel()
    
    private var refreshTimer: Timer?
    private let weatherClient = WeatherClient()
    
    private enum StorageKeys {
        static let controllers = "observatory.controllers"
        static let active = "observatory.controllers.active"
    }
    
    init(initialControllers: [ControllerState] = []) {
        if initialControllers.isEmpty {
            controllers = Self.loadStoredControllers()
            if controllers.isEmpty {
                controllers = [ControllerState(config: .default())]
            }
        } else {
            controllers = initialControllers
        }
        controllers.forEach { attachLogging(to: $0) }
        restoreActiveControllers()
        updateActiveControllerCache()
    }
    
    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            // Only fetch if there are connected controllers
            guard let self = self, !self.connectedControllers.isEmpty else { return }
            self.fetchStatus()
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func controllers(for role: ControllerRole) -> [ControllerState] {
        controllers.filter { $0.roles.contains(role) }
    }
    
    var camerasController: ControllerState? {
        controller(for: .cameras)
    }
    
    func controller(for role: ControllerRole) -> ControllerState? {
        if let id = activeControllerIDs[role],
           let controller = controllers.first(where: { $0.id == id && $0.roles.contains(role) }) {
            return controller
        }
        return controllers.first(where: { $0.roles.contains(role) })
    }
    
    func setActiveController(_ role: ControllerRole, controllerID: UUID) {
        guard controllers.contains(where: { $0.id == controllerID && $0.roles.contains(role) }) else { return }
        activeControllerIDs[role] = controllerID
        persistActiveControllers()
    }
    
    func addController(name: String, baseURL: String, roles: Set<ControllerRole>) {
        var config = ControllerConfig(
            id: UUID(),
            name: name,
            baseURL: baseURL,
            authToken: nil,
            roles: Array(roles.isEmpty ? Set(ControllerRole.allCases) : roles)
        )
        if config.roles.isEmpty {
            config.roles = ControllerRole.allCases
        }
        let controller = ControllerState(config: config)
        attachLogging(to: controller)
        controllers.append(controller)
        persistControllers()
        updateActiveControllerCache()
    }
    
    func removeController(_ controller: ControllerState) {
        controllers.removeAll { $0.id == controller.id }
        activeControllerIDs = activeControllerIDs.filter { $0.value != controller.id }
        persistControllers()
        updateActiveControllerCache()
        persistActiveControllers()
    }
    
    func refreshActiveControllers() {
        updateActiveControllerCache()
    }
    
    func persistControllers() {
        let configs = controllers.map { $0.config }
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: StorageKeys.controllers)
        }
    }
    
    private func attachLogging(to controller: ControllerState) {
        controller.logHandler = { [weak self] entry in
            self?.logs.insert(entry, at: 0)
            self?.trimLogs()
        }
    }
    
    private func trimLogs() {
        if logs.count > 1000 {
            logs = Array(logs.prefix(1000))
        }
    }
    
    private func restoreActiveControllers() {
        guard let stored = UserDefaults.standard.dictionary(forKey: StorageKeys.active) as? [String: String] else { return }
        var mapping: [ControllerRole: UUID] = [:]
        for (rawRole, rawID) in stored {
            guard let role = ControllerRole(rawValue: rawRole),
                  let uuid = UUID(uuidString: rawID) else { continue }
            mapping[role] = uuid
        }
        activeControllerIDs = mapping
    }
    
    private func persistActiveControllers() {
        var dict: [String: String] = [:]
        for (role, id) in activeControllerIDs {
            dict[role.rawValue] = id.uuidString
        }
        UserDefaults.standard.set(dict, forKey: StorageKeys.active)
    }
    
    private func updateActiveControllerCache() {
        for role in ControllerRole.allCases {
            if let id = activeControllerIDs[role],
               controllers.contains(where: { $0.id == id && $0.roles.contains(role) }) {
                continue
            }
            if let fallback = controllers.first(where: { $0.roles.contains(role) }) {
                activeControllerIDs[role] = fallback.id
            }
        }
        persistActiveControllers()
    }
    
    private static func loadStoredControllers() -> [ControllerState] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.controllers),
              let configs = try? JSONDecoder().decode([ControllerConfig].self, from: data) else {
            return []
        }
        return configs.map { ControllerState(config: $0) }
    }
    
    nonisolated func fetchStatus() {
        Task { @MainActor in
            // Only fetch status for connected controllers
            controllers.filter { connectedControllers.contains($0.id) }
                       .forEach { $0.fetchStatus() }
        }
    }
    
    nonisolated func fetchStatus(for controller: ControllerState) {
        Task { @MainActor in
            controller.fetchStatus()
        }
    }
    
    func addLog(level: LogEntry.Level, module: String, message: String, controller: ControllerState? = nil) {
        var entry = LogEntry(ts: Date(), module: module, level: level, message: message, extra: nil)
        entry.controllerID = controller?.id
        entry.controllerName = controller?.name
        logs.insert(entry, at: 0)
        trimLogs()
    }
    
    func fetchWeather() {
        Task {
            do {
                let snapshot = try await weatherClient.fetchCurrentWeather()
                await MainActor.run {
                    self.weather = snapshot
                    self.addLog(
                        level: .info,
                        module: "weather",
                        message: Self.describeWeather(snapshot)
                    )
                }
            } catch {
                let nsError = error as NSError
                var detail = "\(error.localizedDescription) (domain=\(nsError.domain) code=\(nsError.code))"
                if let weatherError = error as? WeatherClient.WeatherError,
                   let sample = weatherError.samplePayload, !sample.isEmpty {
                    detail += " sample=\(sample.prefix(1200))"
                }
                addLog(level: .warn, module: "weather", message: "Weather fetch failed: \(detail)")
            }
        }
    }

    private static func describeWeather(_ snapshot: WeatherModel) -> String {
        func value(_ number: Double?, fmt: String, suffix: String) -> String {
            guard let number else { return "—" }
            return String(format: fmt, number) + suffix
        }
        let temp = value(snapshot.temperatureC, fmt: "%.1f", suffix: "°C")
        let humidity = value(snapshot.humidityPercent, fmt: "%.0f", suffix: "%")
        let wind = value(snapshot.windSpeed, fmt: "%.0f", suffix: " km/h")
        let precip = value(snapshot.precipitationMm, fmt: "%.1f", suffix: " mm")
        return "Weather updated: Temp \(temp), Humidity \(humidity), Wind \(wind), Precip \(precip)"
    }
    
    func startAutoRefresh(interval: TimeInterval = 5.0) {
        refreshTimer?.invalidate()
        guard !controllers.isEmpty else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
            self?.fetchStatus()
                self?.fetchWeather()
            }
        }
        refreshTimer = timer
            RunLoop.main.add(timer, forMode: .common)
    }

    static let preview: AppState = {
        let cameraConfig = ControllerConfig(
            id: UUID(),
            name: "Camera Controller",
            baseURL: "http://demo-camera.local:8080",
            authToken: nil,
            roles: [.cameras]
        )
        let cameraController = ControllerState(config: cameraConfig)
        cameraController.sensors = SensorsModel(
            temperature: 18.5,
            humidity: 65,
            allSkyCam: .init(connected: true, streaming: false, lastSnapshot: Date())
        )
        let state = AppState(initialControllers: [cameraController])
        state.weather = WeatherModel(
            temperatureC: 16.2,
            apparentTemperatureC: 15.7,
            humidityPercent: 70,
            precipitationMm: 0,
            cloudCoverPercent: 45,
            windSpeed: 12,
            windGust: 20,
            observationTime: Date()
        )
        return state
    }()
}

struct SensorsModel {
    var temperature: Double? = nil
    var humidity: Double? = nil
    struct Camera {
        var connected: Bool = false
        var streaming: Bool = false
        var lastSnapshot: Date? = nil
        var fault: String? = nil
    }
    var allSkyCam: Camera = Camera()
}

struct LogEntry: Identifiable {
    let id = UUID()
    var ts: Date
    var controllerID: UUID?
    var controllerName: String?
    var module: String
    enum Level: String { case info, warn, error }
    var level: Level
    var message: String
    var extra: String?
}


