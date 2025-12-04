//
//  MJPEGStreamView.swift
//  Pomfret VISTA Observatory
//
//  Simple and reliable MJPEG stream viewer
//

import SwiftUI
import AppKit
import Combine

struct MJPEGStreamView: View {
    let url: String
    @StateObject private var loader = MJPEGLoader()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if let image = loader.currentImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading stream...")
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                
                // FPS indicator in top-left corner
                if loader.currentImage != nil {
                    VStack {
                        HStack {
                            Text(String(format: "%.1f FPS", loader.fps))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(8)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            loader.startStreaming(url: url)
        }
        .onDisappear {
            loader.stopStreaming()
        }
    }
}

class MJPEGLoader: ObservableObject {
    @Published var currentImage: NSImage?
    @Published var fps: Double = 0.0
    
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var delegate: StreamDelegate?
    private var session: URLSession?
    private var frameCount: Int = 0
    private var lastFPSUpdate: Date = Date()
    private var lastFrameTime: Date?
    
    func startStreaming(url: String) {
        guard let streamURL = URL(string: url) else {
            print("Invalid URL: \(url)")
            return
        }
        
        print("Starting MJPEG stream from: \(url)")
        
        delegate = StreamDelegate { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                self.currentImage = image
                
                // Calculate FPS
                let now = Date()
                self.frameCount += 1
                
                let timeSinceLastUpdate = now.timeIntervalSince(self.lastFPSUpdate)
                if timeSinceLastUpdate >= 1.0 {
                    // Update FPS every second
                    self.fps = Double(self.frameCount) / timeSinceLastUpdate
                    self.frameCount = 0
                    self.lastFPSUpdate = now
                }
            }
        }
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60  // Increased for slow networks
        config.timeoutIntervalForResource = 600  // 10 minutes total
        
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        
        var request = URLRequest(url: streamURL)
        request.timeoutInterval = 60  // Increased for slow networks
        
        task = session?.dataTask(with: request)
        task?.resume()
    }
    
    func stopStreaming() {
        print("Stopping MJPEG stream")
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        delegate = nil
        buffer.removeAll()
        
        // Reset FPS tracking
        DispatchQueue.main.async { [weak self] in
            self?.fps = 0.0
            self?.frameCount = 0
            self?.lastFPSUpdate = Date()
        }
    }
    
    deinit {
        stopStreaming()
    }
}

class StreamDelegate: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private let onImage: (NSImage) -> Void
    
    init(onImage: @escaping (NSImage) -> Void) {
        self.onImage = onImage
        super.init()
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("🔐 Received authentication challenge: \(challenge.protectionSpace.authenticationMethod)")
        
        // Accept self-signed certificates (only for development/testing)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            if let serverTrust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        
        completionHandler(.performDefaultHandling, nil)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        print("📡 Stream response received: \(response)")
        if let httpResponse = response as? HTTPURLResponse {
            print("📡 Status code: \(httpResponse.statusCode)")
            print("📡 Headers: \(httpResponse.allHeaderFields)")
        }
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        print("📡 Received \(data.count) bytes")
        buffer.append(data)
        processFrames()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("❌ Stream error: \(error.localizedDescription)")
            print("❌ Error details: \(error)")
        } else {
            print("✅ Stream completed successfully")
        }
    }
    
    private func processFrames() {
        while let frame = extractFrame() {
            if let image = NSImage(data: frame) {
                onImage(image)
            }
        }
    }
    
    private func extractFrame() -> Data? {
        // Look for JPEG start marker (0xFF 0xD8)
        guard let jpegStart = buffer.firstRange(of: Data([0xFF, 0xD8])) else {
            return nil
        }
        
        // Look for JPEG end marker (0xFF 0xD9) after the start
        let searchRange = jpegStart.upperBound..<buffer.endIndex
        guard let jpegEnd = buffer[searchRange].firstRange(of: Data([0xFF, 0xD9])) else {
            return nil
        }
        
        // Calculate actual end position
        let actualEnd = buffer.startIndex.advanced(by: buffer.distance(from: buffer.startIndex, to: searchRange.lowerBound) + buffer[searchRange].distance(from: searchRange.lowerBound, to: jpegEnd.upperBound))
        
        // Extract the frame
        let frameData = buffer[jpegStart.lowerBound..<actualEnd]
        
        // Remove processed data
        buffer.removeSubrange(buffer.startIndex..<actualEnd)
        
        return Data(frameData)
    }
}

extension Data {
    func firstRange(of data: Data) -> Range<Index>? {
        guard !data.isEmpty, count >= data.count else { return nil }
        
        let searchEnd = endIndex - data.count + 1
        guard searchEnd > startIndex else { return nil }
        
        for i in startIndex..<searchEnd {
            var found = true
            for j in 0..<data.count {
                if self[i + j] != data[j] {
                    found = false
                    break
                }
            }
            if found {
                return i..<(i + data.count)
            }
        }
        return nil
    }
}
