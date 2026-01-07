import Foundation
import Combine

enum ControllerRole: String, Codable, CaseIterable, Identifiable {
    case cameras = "cameras"
    
    var id: String { rawValue }
    
    var displayName: String {
        return "Cameras"
        }
    
    var description: String {
        return "Camera control and image capture"
    }
}

struct ControllerConfig: Identifiable, Codable {
    var id: UUID
    var name: String
    var baseURL: String
    var authToken: String?
    var roles: [ControllerRole]
    
    static func `default`() -> ControllerConfig {
        ControllerConfig(
            id: UUID(),
            name: "Camera Controller",
            baseURL: "http://172.18.3.44:8080",
            authToken: nil,
            roles: [.cameras]
        )
    }
}

@MainActor
final class ControllerState: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var baseURL: String {
        didSet { apiClient?.baseURL = baseURL }
    }
    @Published var authToken: String? {
        didSet { apiClient?.authToken = authToken }
    }
    @Published var roles: Set<ControllerRole>
    
    @Published var sensors = SensorsModel()
    @Published var logs: [LogEntry] = []
    
    var logHandler: ((LogEntry) -> Void)?
    
    private(set) var apiClient: APIClient?
    
    init(config: ControllerConfig) {
        self.id = config.id
        self.name = config.name
        self.baseURL = config.baseURL
        self.authToken = config.authToken
        self.roles = Set(config.roles)
        self.apiClient = APIClient(baseURL: config.baseURL, authToken: config.authToken)
    }
    
    var config: ControllerConfig {
        ControllerConfig(
            id: id,
            name: name,
            baseURL: baseURL,
            authToken: authToken,
            roles: Array(roles)
        )
    }
    
    func fetchStatus() {
        Task {
            await performFetchStatus()
        }
    }
    
    private func performFetchStatus() async {
        guard let apiClient else { return }
        do {
            let status = try await apiClient.fetchStatus()
            updateFromStatus(status)
        } catch {
            addLog(level: .error, module: "api", message: "Failed to fetch status: \(error.localizedDescription)")
        }
    }
    
    private func refreshAfter(delay: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await performFetchStatus()
    }
    
    private func updateFromStatus(_ status: StatusResponse) {
        // Only update fields that this controller provides
        if let sensorsStatus = status.sensors {
            sensors.temperature = sensorsStatus.temperature
            sensors.humidity = sensorsStatus.humidity
            sensors.weatherCam.connected = sensorsStatus.weatherCam.connected
            sensors.weatherCam.streaming = sensorsStatus.weatherCam.streaming
            sensors.weatherCam.fault = sensorsStatus.weatherCam.fault
            sensors.meteorCam.connected = sensorsStatus.meteorCam.connected
            sensors.meteorCam.streaming = sensorsStatus.meteorCam.streaming
            sensors.meteorCam.fault = sensorsStatus.meteorCam.fault
        }
        
        if let alerts = status.alerts {
            for alert in alerts {
            let level = LogEntry.Level(rawValue: alert.level) ?? .info
            addLog(level: level, module: "system", message: alert.message)
        }
        }
    }
    
    func addLog(level: LogEntry.Level, module: String, message: String) {
        var entry = LogEntry(ts: Date(), module: module, level: level, message: message, extra: nil)
        entry.controllerName = name
        entry.controllerID = id
        logs.insert(entry, at: 0)
        if logs.count > 500 {
            logs = Array(logs.prefix(500))
        }
        logHandler?(entry)
    }
}


