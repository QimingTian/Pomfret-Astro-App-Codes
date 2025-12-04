import Foundation
import Combine

class APIClient: NSObject {
    var baseURL: String
    var authToken: String?
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    init(baseURL: String, authToken: String? = nil) {
        self.baseURL = baseURL
        self.authToken = authToken
        super.init()
    }
    
    // MARK: - Status
    
    func fetchStatus() async throws -> StatusResponse {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/status"
        
        print("🌐 [APIClient] Fetching status from: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ [APIClient] Invalid URL: \(urlString)")
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30  // Increased for cross-subnet connections
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Pomfret Observatory/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        print("🌐 [APIClient] Sending request to: \(url)")
        print("🌐 [APIClient] Using URLSession: \(urlSession)")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            print("✅ [APIClient] Received response: \(response)")
            
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ [APIClient] Status code: \(httpResponse.statusCode)")
            }
            
            return try processStatusResponse(data: data, response: response)
        } catch {
            print("❌ [APIClient] Request failed with error: \(error)")
            print("❌ [APIClient] Error type: \(type(of: error))")
            print("❌ [APIClient] Error details: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("❌ [APIClient] URLError code: \(urlError.code.rawValue)")
                print("❌ [APIClient] URLError description: \(urlError.localizedDescription)")
            }
            throw error
        }
    }
    
    private func processStatusResponse(data: Data, response: URLResponse) throws -> StatusResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(StatusResponse.self, from: data)
    }
    
    // MARK: - Roof Control
    
    func openRoof() async throws -> OperationResponse {
        return try await post("/roof/open")
    }
    
    func closeRoof() async throws -> OperationResponse {
        return try await post("/roof/close")
    }
    
    func stopRoof() async throws {
        try await postEmpty("/roof/stop")
    }
    
    func lockMagLock() async throws {
        try await postEmpty("/roof/lock")
    }
    
    func unlockMagLock() async throws {
        try await postEmpty("/roof/unlock")
    }
    
    // MARK: - Camera Control
    
    func startCameraStream() async throws {
        try await postEmpty("/camera/stream/start")
    }
    
    func stopCameraStream() async throws {
        try await postEmpty("/camera/stream/stop")
    }
    
    func updateCameraSettings(gain: Int? = nil, photoExposure: Int? = nil) async throws {
        var params: [String: Any] = [:]
        if let gain = gain {
            params["gain"] = gain
        }
        if let photoExp = photoExposure {
            params["photo_exposure"] = photoExp
        }
        
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/camera/settings"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Pomfret Observatory/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        
        print("🌐 [APIClient] Sending camera settings update")
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
    
    func captureSnapshot() async throws -> Data {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/camera/snapshot"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Pomfret Observatory/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return data
    }
    
    // MARK: - Helper Methods
    
    private func post(_ path: String) async throws -> OperationResponse {
        return try await post(path, responseType: OperationResponse.self)
    }
    
    private func postEmpty(_ path: String) async throws {
        _ = try await post(path, responseType: EmptyResponse.self)
    }
    
    private func post<T: Decodable>(_ path: String, responseType: T.Type) async throws -> T {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += path
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30  // Increased for cross-subnet connections
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Pomfret Observatory/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        if data.isEmpty || String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Response Models

struct StatusResponse: Codable {
    let roof: RoofStateResponse?
    let sensors: SensorsStateResponse?
    let safety: SafetyStateResponse?
    let alerts: [AlertResponse]?
}

struct RoofStateResponse: Codable {
    let state: String
    let openLimit: Bool
    let closeLimit: Bool
    let currentA: Double?
    let magLockEngaged: Bool
    let fault: String?
}

struct SensorsStateResponse: Codable {
    let temperature: Double?
    let humidity: Double?
    let weatherCam: CameraStateResponse
    let meteorCam: CameraStateResponse
}

struct CameraStateResponse: Codable {
    let connected: Bool
    let streaming: Bool
    let lastSnapshot: String?
    let fault: String?
}

struct SafetyStateResponse: Codable {
    let rain: Bool
    let windHigh: Bool
    let doorOpen: Bool
    let powerOk: Bool
    let safeToOpenRoof: Bool
}

struct AlertResponse: Codable {
    let level: String
    let message: String
    let ts: String
}

struct OperationResponse: Codable {
    let opId: String?
}

struct EmptyResponse: Codable { }

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - URLSessionDelegate

extension APIClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("🔐 [APIClient] Received authentication challenge")
        print("🔐 [APIClient] Authentication method: \(challenge.protectionSpace.authenticationMethod)")
        print("🔐 [APIClient] Host: \(challenge.protectionSpace.host)")
        
        // Accept all SSL certificates (including self-signed and Cloudflare certificates)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            print("🔐 [APIClient] Server trust authentication")
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                print("✅ [APIClient] Accepting server trust certificate")
                completionHandler(.useCredential, credential)
                return
            }
        }
        
        print("⚠️ [APIClient] Using default handling for authentication challenge")
        completionHandler(.performDefaultHandling, nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ [APIClient] URLSession task completed with error: \(error)")
            print("❌ [APIClient] Error details: \(error.localizedDescription)")
        } else {
            print("✅ [APIClient] URLSession task completed successfully")
        }
    }
}
