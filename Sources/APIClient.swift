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
        
        guard let url = URL(string: urlString) else {
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
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            return try processStatusResponse(data: data, response: response)
        } catch {
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
    
    // MARK: - Camera Control
    
    func startCameraStream() async throws {
        try await postEmpty("/camera/stream/start")
    }
    
    func stopCameraStream() async throws {
        try await postEmpty("/camera/stream/stop")
    }
    
    func updateCameraSettings(gain: Int? = nil, photoExposure: Int? = nil, videoExposure: Int? = nil, imageFormat: String? = nil, wbR: Int? = nil, wbB: Int? = nil, wbAuto: Bool? = nil) async throws {
        var params: [String: Any] = [:]
        if let gain = gain {
            params["gain"] = gain
        }
        if let photoExp = photoExposure {
            params["photo_exposure"] = photoExp
        }
        if let videoExp = videoExposure {
            params["video_exposure"] = videoExp
        }
        if let format = imageFormat {
            params["image_format"] = format
        }
        if let wbR = wbR {
            params["wb_r"] = wbR
        }
        if let wbB = wbB {
            params["wb_b"] = wbB
        }
        if let wbAuto = wbAuto {
            params["wb_auto"] = wbAuto
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
            // Try to extract error message from response body if it's JSON
            var errorMessage: String? = nil
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                errorMessage = error
            }
            if let errorMsg = errorMessage {
                throw APIError.httpErrorWithMessage(httpResponse.statusCode, errorMsg)
            } else {
                throw APIError.httpError(httpResponse.statusCode)
            }
        }
        
        return data
    }
    
    // MARK: - Sequence Capture
    
    struct SequenceStatus: Codable {
        let active: Bool
        let currentCount: Int
        let totalCount: Int
        let savePath: String?
        let fileFormat: String?
        let interval: Double?
        
        enum CodingKeys: String, CodingKey {
            case active
            case currentCount = "current_count"
            case totalCount = "total_count"
            case savePath = "save_path"
            case fileFormat = "file_format"
            case interval
        }
    }
    
    struct SequenceStartResponse: Codable {
        let success: Bool
        let message: String
        let savePath: String
        let count: Int
        let fileFormat: String
        let interval: Double?
        
        enum CodingKeys: String, CodingKey {
            case success, message
            case savePath = "save_path"
            case count
            case fileFormat = "file_format"
            case interval
        }
    }
    
    func startSequence(savePath: String, count: Int, fileFormat: String, interval: Double = 0) async throws -> SequenceStartResponse {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/camera/sequence/start"
        
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
        
        var params: [String: Any] = [
            "save_path": savePath,
            "count": count,
            "file_format": fileFormat
        ]
        if interval > 0 {
            params["interval"] = interval
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to decode error message from response
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw APIError.httpErrorWithMessage(httpResponse.statusCode, errorMessage)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(SequenceStartResponse.self, from: data)
    }
    
    func stopSequence() async throws {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/camera/sequence/stop"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Pomfret Observatory/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
    }
    
    func getSequenceStatus() async throws -> SequenceStatus {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/camera/sequence/status"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
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
        
        return try JSONDecoder().decode(SequenceStatus.self, from: data)
    }
    
    struct SequenceCaptureResponse: Codable {
        let success: Bool
        let count: Int
        let photos: [String?]  // Base64 encoded JPEG images
    }
    
    func captureSequence(count: Int) async throws -> SequenceCaptureResponse {
        var urlString = baseURL.trimmingCharacters(in: .whitespaces)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }
        urlString += "/camera/sequence/capture"
        
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300  // 5 minutes for sequence capture
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Pomfret Observatory/1.1 (macOS)", forHTTPHeaderField: "User-Agent")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let params: [String: Any] = ["count": count]
        request.httpBody = try JSONSerialization.data(withJSONObject: params)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorData["error"] {
                throw APIError.httpErrorWithMessage(httpResponse.statusCode, errorMessage)
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(SequenceCaptureResponse.self, from: data)
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
    let sensors: SensorsStateResponse?
    let alerts: [AlertResponse]?
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
    case httpErrorWithMessage(Int, String)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .httpErrorWithMessage(let code, let message):
            return "HTTP error: \(code) - \(message)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - URLSessionDelegate

extension APIClient: URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Accept all SSL certificates (including self-signed and Cloudflare certificates)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        
        completionHandler(.performDefaultHandling, nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Task completed
    }
}
