import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let cameraImageFormats: [String] = ["RGB24", "RAW8", "RAW16", "Y8"]

private struct SensorsPanel<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct MissingSensorsControllerCard: View {
    var body: some View {
        SensorsPanel(title: "Sensors", icon: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("No sensors controller configured")
                    .font(.headline)
                Text("Add a sensors-capable controller in Settings to view data.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// Document class for fileExporter
struct ImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.jpeg, .png, .tiff] }
    
    var data: Data
    var contentType: UTType
    
    init(data: Data, contentType: UTType = .jpeg) {
        self.data = data
        self.contentType = contentType
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.contentType = configuration.contentType
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

// Simple photo viewer sheet
private struct PhotoViewerSheet: View {
    let image: NSImage
    let gain: Int
    let exposure: Double
    @Environment(\.dismiss) var dismiss
    @State private var saveSuccessMessage: String?
    @State private var showSavePanel = false
    @State private var document: ImageDocument?
    @State private var fileFormat: FileFormat = .jpeg
    private let jpegQuality: Double = 1.0  // Always use 100% quality
    
    enum FileFormat: String, CaseIterable {
        case jpeg = "JPEG"
        case png = "PNG"
        case tiff = "TIFF"
        
        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .tiff: return .tiff
            }
        }
        
        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .tiff: return "tiff"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Captured Photo")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                
                if let message = saveSuccessMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                }
                
                // File format selector - in top right, next to Save button
                HStack(spacing: 6) {
                    Text("Format:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Picker("", selection: $fileFormat) {
                        ForEach(FileFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
                .padding(.trailing, 1)
                
                Button("Save") {
                    prepareSave()
                }
                .buttonStyle(.bordered)
                .fileExporter(
                    isPresented: $showSavePanel,
                    document: document,
                    contentType: fileFormat.utType,
                    defaultFilename: generateDefaultFilename()
                ) { result in
                    handleSaveResult(result)
                }
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            
            Divider()
            
            HStack(spacing: 12) {
                Text("Size: \(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Gain: \(gain)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(String(format: "Exposure: %.3f s", exposure))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 800, height: 700)
    }
    
    private func generateDefaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        return "\(timestamp)_gain\(gain)_exp\(String(format: "%.3f", exposure))s.\(fileFormat.fileExtension)"
    }
    
    private func prepareSave() {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            saveSuccessMessage = "Save failed: Could not convert image"
            return
        }
        
        var imageData: Data?
        
        switch fileFormat {
        case .jpeg:
            imageData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
        case .png:
            imageData = bitmapImage.representation(using: .png, properties: [:])
        case .tiff:
            imageData = bitmapImage.representation(using: .tiff, properties: [:])
        }
        
        guard let data = imageData else {
            saveSuccessMessage = "Save failed: Could not encode image"
            return
        }
        
        // Create document for fileExporter
        document = ImageDocument(data: data, contentType: fileFormat.utType)
        showSavePanel = true
    }
    
    private func handleSaveResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            saveSuccessMessage = "Saved!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                saveSuccessMessage = nil
            }
        case .failure(let error):
            saveSuccessMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}

// Helper functions for progress tracking
private func startSequenceProgressTimer(total: Int, estimatedTime: Double, active: Binding<Bool>, currentCount: Binding<Int>, progressTimer: Binding<Timer?>, startTimeString: Binding<String>) {
    // Stop existing timer if any
    progressTimer.wrappedValue?.invalidate()
    
    // Create timer to update progress based on elapsed time
    let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
        guard active.wrappedValue,
              !startTimeString.wrappedValue.isEmpty,
              let timeInterval = TimeInterval(startTimeString.wrappedValue) else {
            progressTimer.wrappedValue?.invalidate()
            progressTimer.wrappedValue = nil
            return
        }
        
        let startTime = Date(timeIntervalSince1970: timeInterval)
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(elapsed / estimatedTime, 1.0)
        let estimatedCurrent = Int(Double(total) * progress)
        
        Task { @MainActor in
            currentCount.wrappedValue = min(estimatedCurrent, total)
            
            // Stop timer if we've reached the end
            if progress >= 1.0 {
                progressTimer.wrappedValue?.invalidate()
                progressTimer.wrappedValue = nil
            }
        }
    }
    
    progressTimer.wrappedValue = timer
    RunLoop.main.add(timer, forMode: .common)
}

private func startPhotoCaptureProgressTimer(exposureTime: Double, active: Binding<Bool>, startTime: Binding<String>, progressTimer: Binding<Timer?>, progressValue: Binding<Double>) {
    // Stop existing timer if any
    progressTimer.wrappedValue?.invalidate()
    
    // Reset progress
    progressValue.wrappedValue = 0.0
    
    // Create timer to update progress based on elapsed time
    let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
        guard active.wrappedValue,
              !startTime.wrappedValue.isEmpty,
              let timeInterval = TimeInterval(startTime.wrappedValue) else {
            progressTimer.wrappedValue?.invalidate()
            progressTimer.wrappedValue = nil
            progressValue.wrappedValue = 0.0
            return
        }
        
        let startTimeDate = Date(timeIntervalSince1970: timeInterval)
        let elapsed = Date().timeIntervalSince(startTimeDate)
        let progress = min(elapsed / exposureTime, 1.0)
        
        // Update progress value
        Task { @MainActor in
            progressValue.wrappedValue = progress
        }
        
        // Stop timer if we've reached the end
        if progress >= 1.0 {
            progressTimer.wrappedValue?.invalidate()
            progressTimer.wrappedValue = nil
            progressValue.wrappedValue = 1.0
        }
    }
    
    progressTimer.wrappedValue = timer
    RunLoop.main.add(timer, forMode: .common)
}

private func photoCaptureProgress(photoExposure: Double, startTime: String) -> Double {
    guard !startTime.isEmpty,
          let timeInterval = TimeInterval(startTime) else {
        return 0.0
    }
    
    let startTimeDate = Date(timeIntervalSince1970: timeInterval)
    let elapsed = Date().timeIntervalSince(startTimeDate)
    return min(elapsed / photoExposure, 1.0)
}

private func stopSequence(controller: ControllerState, appState: AppState, active: Binding<Bool>, statusTimer: Binding<Timer?>, startTimeString: Binding<String>) {
    // Just set active to false, the capture loop will check this and stop
    active.wrappedValue = false
    statusTimer.wrappedValue?.invalidate()
    statusTimer.wrappedValue = nil
    startTimeString.wrappedValue = ""
    appState.addLog(level: .info, module: "camera", message: "Stopping sequence capture...", controller: controller)
}

private func updateCameraSetting(controller: ControllerState, gain: Int? = nil, photoExposure: Double? = nil, videoExposure: Double? = nil, imageFormat: String? = nil, wbR: Int? = nil, wbB: Int? = nil, wbAuto: Bool? = nil, appState: AppState, streamRefreshID: Binding<UUID>? = nil) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { 
                appState.addLog(level: .error, module: "camera", message: "API client not available", controller: controller)
                return
            }
            
            var photoExpMicroseconds: Int?
            var videoExpMicroseconds: Int?
            let wasStreaming = controller.sensors.weatherCam.streaming || controller.sensors.meteorCam.streaming
            
            if let exp = photoExposure {
                photoExpMicroseconds = Int(exp * 1_000_000)
                appState.addLog(level: .info, module: "camera", message: String(format: "Sending photo exposure: %.3f s", exp), controller: controller)
            }
            
            if let exp = videoExposure {
                videoExpMicroseconds = Int(exp * 1_000_000)
                appState.addLog(level: .info, module: "camera", message: String(format: "Sending video exposure: %.3f s", exp), controller: controller)
            }
            
            if let g = gain {
                appState.addLog(level: .info, module: "camera", message: "Sending gain: \(g)", controller: controller)
            }
            
            if let format = imageFormat {
                appState.addLog(level: .info, module: "camera", message: "Sending image format: \(format)", controller: controller)
            }
            
            if let wbR = wbR {
                appState.addLog(level: .info, module: "camera", message: "Sending white balance R: \(wbR)", controller: controller)
            }
            
            if let wbB = wbB {
                appState.addLog(level: .info, module: "camera", message: "Sending white balance B: \(wbB)", controller: controller)
            }
            
            if let wbAuto = wbAuto {
                appState.addLog(level: .info, module: "camera", message: "Sending white balance auto: \(wbAuto)", controller: controller)
            }
            
            try await apiClient.updateCameraSettings(gain: gain, photoExposure: photoExpMicroseconds, videoExposure: videoExpMicroseconds, imageFormat: imageFormat, wbR: wbR, wbB: wbB, wbAuto: wbAuto)
            
            if let g = gain {
                appState.addLog(level: .info, module: "camera", message: "✓ Gain set to \(g)", controller: controller)
                
                // If was streaming, wait for stream to restart and force refresh stream view
                if wasStreaming {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    controller.fetchStatus()
                    
                    // Force refresh stream view by changing its ID
                    await MainActor.run {
                        streamRefreshID?.wrappedValue = UUID()
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Stream refreshed with new gain", controller: controller)
                }
            }
            if let exp = photoExposure {
                appState.addLog(level: .info, module: "camera", message: "✓ Photo exposure set to \(String(format: "%.3f", exp)) s", controller: controller)
            }
            if let exp = videoExposure {
                appState.addLog(level: .info, module: "camera", message: "✓ Video exposure set to \(String(format: "%.3f", exp)) s", controller: controller)
                
                // If was streaming, wait for stream to restart and force refresh stream view
                if wasStreaming {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    controller.fetchStatus()
                    
                    // Force refresh stream view by changing its ID
                    await MainActor.run {
                        streamRefreshID?.wrappedValue = UUID()
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Stream refreshed with new video exposure", controller: controller)
                }
            }
            if let format = imageFormat {
                appState.addLog(level: .info, module: "camera", message: "✓ Image format set to \(format) (only affects photo capture, not video stream)", controller: controller)
                // Note: Image format only affects photo capture, not video streaming
                // Video stream always uses RGB24 format for real-time performance
            }
            
            if let wbR = wbR {
                appState.addLog(level: .info, module: "camera", message: "✓ White balance R set to \(wbR)", controller: controller)
                
                // If was streaming, wait for stream to restart and force refresh stream view
                if wasStreaming {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    controller.fetchStatus()
                    
                    await MainActor.run {
                        streamRefreshID?.wrappedValue = UUID()
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Stream refreshed with new white balance R", controller: controller)
                }
            }
            
            if let wbB = wbB {
                appState.addLog(level: .info, module: "camera", message: "✓ White balance B set to \(wbB)", controller: controller)
                
                // If was streaming, wait for stream to restart and force refresh stream view
                if wasStreaming {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    controller.fetchStatus()
                    
                    await MainActor.run {
                        streamRefreshID?.wrappedValue = UUID()
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Stream refreshed with new white balance B", controller: controller)
                }
            }
            
            if let wbAuto = wbAuto {
                appState.addLog(level: .info, module: "camera", message: "✓ White balance auto set to \(wbAuto ? "enabled" : "disabled")", controller: controller)
                
                // If was streaming, wait for stream to restart and force refresh stream view
                if wasStreaming {
                    try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    controller.fetchStatus()
                    
                    await MainActor.run {
                        streamRefreshID?.wrappedValue = UUID()
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Stream refreshed with new white balance mode", controller: controller)
                }
            }
        } catch {
            appState.addLog(level: .error, module: "camera", message: "Failed to update settings: \(error.localizedDescription)", controller: controller)
        }
    }
}

struct SensorsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Cameras (from cameras controller)
                if let controller = appState.camerasController {
                    CombinedCameraSection(controller: controller)
                } else {
                    // Show message if nothing is configured
                    MissingSensorsControllerCard()
                }
            }
            .padding()
        }
    }
}

private struct CombinedCameraSection: View {
    @ObservedObject var controller: ControllerState
    @EnvironmentObject var appState: AppState
           @AppStorage("camera.gain") private var gain: Double = 50
           @AppStorage("camera.photoExposure") private var photoExposure: Double = 1.0  // seconds - for photo capture
           @AppStorage("camera.videoExposure") private var videoExposure: Double = 0.1  // seconds - max exposure for video streaming (controls frame rate)
           @AppStorage("camera.imageFormat") private var imageFormat: String = "RGB24"  // Camera capture format
           @AppStorage("camera.wbR") private var wbR: Double = 50  // White balance red channel (range 1-100)
           @AppStorage("camera.wbB") private var wbB: Double = 50  // White balance blue channel (range 1-100)
           @AppStorage("camera.wbAuto") private var wbAuto: Bool = false  // Auto white balance enabled
    @State private var capturedImage: NSImage?
    @State private var capturedGain: Int = 50
    @State private var capturedExposure: Double = 1.0
    @State private var showingPhotoViewer = false
    @State private var streamRefreshID = UUID()  // Force stream refresh
    
    // Single photo capture progress
    @State private var photoCaptureActive: Bool = false
    @State private var photoCaptureStartTime: String = ""
    @State private var photoCaptureProgressTimer: Timer?
    @State private var photoCaptureProgressValue: Double = 0.0
    
    // Sequence capture state
    @AppStorage("sequence.savePath") private var sequenceSavePath: String = ""
    @AppStorage("sequence.bookmark") private var sequenceBookmarkData: Data = Data()
    @AppStorage("sequence.count") private var sequenceCount: Int = 10
    @AppStorage("sequence.fileFormat") private var sequenceFileFormat: String = "JPEG"
    @AppStorage("sequence.active") private var sequenceActive: Bool = false
    @AppStorage("sequence.currentCount") private var sequenceCurrentCount: Int = 0
    @AppStorage("sequence.totalCount") private var sequenceTotalCount: Int = 0
    @AppStorage("sequence.startTime") private var sequenceStartTimeString: String = ""
    @AppStorage("sequence.interval") private var sequenceInterval: Double = 0  // 0 = fast mode, >0 = time-lapse interval in seconds
    @State private var sequenceProgressTimer: Timer?
    
    // Computed property to convert between Date and String for AppStorage
    private var sequenceStartTime: Date? {
        get {
            guard !sequenceStartTimeString.isEmpty,
                  let timeInterval = TimeInterval(sequenceStartTimeString) else {
                return nil
            }
            return Date(timeIntervalSince1970: timeInterval)
        }
        set {
            if let date = newValue {
                sequenceStartTimeString = String(date.timeIntervalSince1970)
            } else {
                sequenceStartTimeString = ""
            }
        }
    }
    
    var body: some View {
        cameraCard(
            title: "Weather & Meteor Monitor Camera",
            primaryCamera: controller.sensors.weatherCam,
            secondaryCamera: controller.sensors.meteorCam,
            controller: controller,
            appState: appState,
            gain: $gain,
            photoExposure: $photoExposure,
            videoExposure: $videoExposure,
            imageFormat: $imageFormat,
            capturedImage: $capturedImage,
            capturedGain: $capturedGain,
            capturedExposure: $capturedExposure,
            showingPhotoViewer: $showingPhotoViewer,
            streamRefreshID: $streamRefreshID,
            photoCaptureActive: $photoCaptureActive,
            photoCaptureStartTime: $photoCaptureStartTime,
            photoCaptureProgressTimer: $photoCaptureProgressTimer,
            photoCaptureProgressValue: $photoCaptureProgressValue,
            sequenceSavePath: $sequenceSavePath,
            sequenceBookmarkData: $sequenceBookmarkData,
            sequenceCount: $sequenceCount,
            sequenceFileFormat: $sequenceFileFormat,
            sequenceActive: $sequenceActive,
            sequenceCurrentCount: $sequenceCurrentCount,
            sequenceTotalCount: $sequenceTotalCount,
            sequenceProgressTimer: $sequenceProgressTimer,
            sequenceStartTimeString: $sequenceStartTimeString,
            sequenceInterval: $sequenceInterval,
            photoExposureValue: photoExposure,
            wbR: $wbR,
            wbB: $wbB,
            wbAuto: $wbAuto
        )
        .sheet(isPresented: $showingPhotoViewer) {
            if let image = capturedImage {
                PhotoViewerSheet(image: image, gain: capturedGain, exposure: capturedExposure)
            }
        }
        .onAppear {
            // Restore progress timer if sequence is active
            if sequenceActive, !sequenceStartTimeString.isEmpty,
               let timeInterval = TimeInterval(sequenceStartTimeString) {
                let startTime = Date(timeIntervalSince1970: timeInterval)
                let elapsed = Date().timeIntervalSince(startTime)
                // Calculate estimated time: (exposure + interval) * count
                let interval = sequenceInterval
                let estimatedTime: Double
                if interval > 0 {
                    estimatedTime = (photoExposure + interval) * Double(sequenceTotalCount)
                } else {
                    estimatedTime = photoExposure * Double(sequenceTotalCount)
                }
                if elapsed < estimatedTime {
                    // Sequence still in progress, restart progress timer
                    startSequenceProgressTimer(
                        total: sequenceTotalCount,
                        estimatedTime: estimatedTime,
                        active: $sequenceActive,
                        currentCount: $sequenceCurrentCount,
                        progressTimer: $sequenceProgressTimer,
                        startTimeString: $sequenceStartTimeString
                    )
                } else {
                    // Sequence should have completed, reset state
                    sequenceActive = false
                    sequenceStartTimeString = ""
                }
            }
        }
    }
}

@ViewBuilder
private func cameraCard(title: String, primaryCamera: SensorsModel.Camera, secondaryCamera: SensorsModel.Camera, controller: ControllerState, appState: AppState, gain: Binding<Double>, photoExposure: Binding<Double>, videoExposure: Binding<Double>, imageFormat: Binding<String>, capturedImage: Binding<NSImage?>, capturedGain: Binding<Int>, capturedExposure: Binding<Double>, showingPhotoViewer: Binding<Bool>, streamRefreshID: Binding<UUID>, photoCaptureActive: Binding<Bool>, photoCaptureStartTime: Binding<String>, photoCaptureProgressTimer: Binding<Timer?>, photoCaptureProgressValue: Binding<Double>, sequenceSavePath: Binding<String>, sequenceBookmarkData: Binding<Data>, sequenceCount: Binding<Int>, sequenceFileFormat: Binding<String>, sequenceActive: Binding<Bool>, sequenceCurrentCount: Binding<Int>, sequenceTotalCount: Binding<Int>, sequenceProgressTimer: Binding<Timer?>, sequenceStartTimeString: Binding<String>, sequenceInterval: Binding<Double>, photoExposureValue: Double, wbR: Binding<Double>, wbB: Binding<Double>, wbAuto: Binding<Bool>) -> some View {
    let isControllerConnected = appState.connectedControllers.contains(controller.id)
    
    SensorsPanel(title: title, icon: "camera.fill") {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(text: primaryCamera.connected ? "Connected" : "Disconnected", status: primaryCamera.connected ? .ok : .error)
                if primaryCamera.streaming || secondaryCamera.streaming {
                    StatusBadge(text: "Streaming", status: .caution)
                }
            }
            if let lastSnap = primaryCamera.lastSnapshot ?? secondaryCamera.lastSnapshot {
                Text("Last snapshot: \(lastSnap, style: .relative)").font(.caption).foregroundColor(.secondary)
            }
            
            // Camera Settings
            VStack(alignment: .leading, spacing: 8) {
                Text("Camera Settings").font(.subheadline).foregroundColor(.secondary)
                
                HStack {
                    Text("Gain:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: gain, in: 0...600, step: 1)
                    TextField("", value: gain, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Button("Set") {
                        updateCameraSetting(controller: controller, gain: Int(gain.wrappedValue), appState: appState, streamRefreshID: streamRefreshID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Photo Exp:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: photoExposure, in: 0.01...1000.0, step: 0.001)
                    TextField("", value: photoExposure, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Button("Set") {
                        updateCameraSetting(controller: controller, photoExposure: photoExposure.wrappedValue, appState: appState)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Video Exp:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: videoExposure, in: 0.001...0.1, step: 0.001)
                    TextField("", value: videoExposure, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Button("Set") {
                        updateCameraSetting(controller: controller, videoExposure: videoExposure.wrappedValue, appState: appState, streamRefreshID: streamRefreshID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Format:")
                        .frame(width: 80, alignment: .leading)
                    Picker(selection: imageFormat, label: EmptyView()) {
                        ForEach(cameraImageFormats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                    Button("Set") {
                        updateCameraSetting(controller: controller, imageFormat: imageFormat.wrappedValue, appState: appState, streamRefreshID: streamRefreshID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Text("WB Auto:")
                        .frame(width: 80, alignment: .leading)
                    HStack(alignment: .center, spacing: 8) {
                        Toggle("", isOn: wbAuto)
                        Button("Set") {
                            updateCameraSetting(controller: controller, wbAuto: wbAuto.wrappedValue, appState: appState, streamRefreshID: streamRefreshID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                HStack {
                    Text("WB R:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: wbR, in: 0...100, step: 1)
                        .disabled(wbAuto.wrappedValue)
                    TextField("", value: wbR, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .disabled(wbAuto.wrappedValue)
                    Button("Set") {
                        updateCameraSetting(controller: controller, wbR: Int(wbR.wrappedValue), appState: appState, streamRefreshID: streamRefreshID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(wbAuto.wrappedValue)
                }
                
                HStack {
                    Text("WB B:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: wbB, in: 0...100, step: 1)
                        .disabled(wbAuto.wrappedValue)
                    TextField("", value: wbB, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        .disabled(wbAuto.wrappedValue)
                    Button("Set") {
                        updateCameraSetting(controller: controller, wbB: Int(wbB.wrappedValue), appState: appState, streamRefreshID: streamRefreshID)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(wbAuto.wrappedValue)
                }
            }
            .disabled(!isControllerConnected)
            .padding(.vertical, 4)
            
            HStack {
                Button("Start Stream") {
                    startStream(controller: controller, appState: appState)
                }
                .disabled(!isControllerConnected || !primaryCamera.connected || primaryCamera.streaming)
                
                Button("Stop Stream") {
                    stopStream(controller: controller, appState: appState)
                }
                .disabled(!isControllerConnected || !primaryCamera.streaming)
                
                Button(action: {
                    capturePhoto(controller: controller, appState: appState, gain: gain, photoExposure: photoExposure, capturedImage: capturedImage, capturedGain: capturedGain, capturedExposure: capturedExposure, showingPhotoViewer: showingPhotoViewer, streamRefreshID: streamRefreshID, active: photoCaptureActive, startTime: photoCaptureStartTime, progressTimer: photoCaptureProgressTimer, progressValue: photoCaptureProgressValue)
                }) {
                    Label("Capture Photo", systemImage: "camera")
                }
                .disabled(!isControllerConnected || !primaryCamera.connected || photoCaptureActive.wrappedValue)
                .buttonStyle(.borderedProminent)
                
                if photoCaptureActive.wrappedValue {
                    ProgressView(value: photoCaptureProgressValue.wrappedValue, total: 1.0)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Sequence Capture Section
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Sequence Capture").font(.subheadline).foregroundColor(.secondary)
                
                HStack {
                    Text("Save Path:")
                        .frame(width: 80, alignment: .leading)
                    TextField("Select folder...", text: sequenceSavePath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("Browse...") {
                        selectSequenceSavePath(savePath: sequenceSavePath, bookmarkData: sequenceBookmarkData)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Count:")
                        .frame(width: 80, alignment: .leading)
                    Stepper(value: sequenceCount, in: 1...10000, step: 1) {
                        TextField("", value: sequenceCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                
                HStack {
                    Text("Format:")
                        .frame(width: 80, alignment: .leading)
                    Picker(selection: sequenceFileFormat, label: EmptyView()) {
                        Text("JPEG").tag("JPEG")
                        Text("PNG").tag("PNG")
                        Text("TIFF").tag("TIFF")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                HStack {
                    Text("Interval:")
                        .frame(width: 80, alignment: .leading)
                    TextField("0 = fast", value: sequenceInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Button("Set") {
                        // Interval is automatically saved via @AppStorage, but we can show confirmation
                        appState.addLog(level: .info, module: "camera", message: "Interval set to \(String(format: "%.1f", sequenceInterval.wrappedValue))s", controller: controller)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if sequenceActive.wrappedValue {
                    HStack {
                        ProgressView(value: Double(sequenceCurrentCount.wrappedValue), total: Double(sequenceTotalCount.wrappedValue))
                            .frame(maxWidth: .infinity)
                        Text("\(sequenceCurrentCount.wrappedValue)/\(sequenceTotalCount.wrappedValue)")
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 80, alignment: .trailing)
                    }
                }
                
                HStack {
                    Button(action: {
                        startSequence(controller: controller, appState: appState, savePath: sequenceSavePath, bookmarkData: sequenceBookmarkData, count: sequenceCount, fileFormat: sequenceFileFormat, interval: sequenceInterval, active: sequenceActive, currentCount: sequenceCurrentCount, totalCount: sequenceTotalCount, progressTimer: sequenceProgressTimer, startTimeString: sequenceStartTimeString, gain: gain, photoExposure: photoExposure)
                    }) {
                        Label("Start Sequence", systemImage: "play.fill")
                    }
                    .disabled(!isControllerConnected || !primaryCamera.connected || sequenceActive.wrappedValue || sequenceSavePath.wrappedValue.isEmpty)
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: {
                        stopSequence(controller: controller, appState: appState, active: sequenceActive, statusTimer: sequenceProgressTimer, startTimeString: sequenceStartTimeString)
                    }) {
                        Label("Stop Sequence", systemImage: "stop.fill")
                    }
                    .disabled(!isControllerConnected || !sequenceActive.wrappedValue)
                    .buttonStyle(.bordered)
                }
            }
            .disabled(!isControllerConnected)
            .padding(.vertical, 4)
            if primaryCamera.streaming {
                ZStack {
                    MJPEGStreamView(url: "\(controller.baseURL)/camera/stream")
                        .frame(height: 500)
                        .id(streamRefreshID.wrappedValue)  // Force refresh when ID changes
                    
                    // LIVE 指示器
                    VStack {
                        HStack {
                            Spacer()
                            HStack {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text("LIVE")
                                    .font(.caption)
                                    .bold()
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 200)
                .cornerRadius(8)
                .overlay {
                    if !primaryCamera.connected {
                        Text("Camera not connected").foregroundColor(.secondary)
                        } else {
                            Text("Click 'Start Stream' to view live feed").foregroundColor(.secondary)
                        }
                    }
                }
        }
    }
}

private func startStream(controller: ControllerState, appState: AppState) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { return }
            try await apiClient.startCameraStream()
            appState.addLog(level: .info, module: "camera", message: "Started camera stream", controller: controller)
            // Refresh status to update UI
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            controller.fetchStatus()
        } catch {
            appState.addLog(level: .error, module: "camera", message: "Failed to start stream: \(error.localizedDescription)", controller: controller)
        }
    }
}

private func stopStream(controller: ControllerState, appState: AppState) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { return }
            try await apiClient.stopCameraStream()
            appState.addLog(level: .info, module: "camera", message: "Stopped camera stream", controller: controller)
            // Refresh status to update UI
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            controller.fetchStatus()
        } catch {
            appState.addLog(level: .error, module: "camera", message: "Failed to stop stream: \(error.localizedDescription)", controller: controller)
        }
    }
}

private func capturePhoto(controller: ControllerState, appState: AppState, gain: Binding<Double>, photoExposure: Binding<Double>, capturedImage: Binding<NSImage?>, capturedGain: Binding<Int>, capturedExposure: Binding<Double>, showingPhotoViewer: Binding<Bool>, streamRefreshID: Binding<UUID>, active: Binding<Bool>, startTime: Binding<String>, progressTimer: Binding<Timer?>, progressValue: Binding<Double>) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { return }
            
            // Start progress tracking
            let exposureTime = photoExposure.wrappedValue
            let startTimestamp = Date().timeIntervalSince1970
            await MainActor.run {
                active.wrappedValue = true
                startTime.wrappedValue = String(startTimestamp)
                
                // Start progress timer
                startPhotoCaptureProgressTimer(
                    exposureTime: exposureTime,
                    active: active,
                    startTime: startTime,
                    progressTimer: progressTimer,
                    progressValue: progressValue
                )
            }
            
            appState.addLog(level: .info, module: "camera", message: "Capturing photo (exposure: \(String(format: "%.3f", exposureTime))s)...", controller: controller)
            
            let imageData = try await apiClient.captureSnapshot()
            
            if let image = NSImage(data: imageData) {
                await MainActor.run {
                    capturedImage.wrappedValue = image
                    capturedGain.wrappedValue = Int(gain.wrappedValue)
                    capturedExposure.wrappedValue = photoExposure.wrappedValue
                    showingPhotoViewer.wrappedValue = true
                    
                    // Stop progress tracking
                    active.wrappedValue = false
                    startTime.wrappedValue = ""
                    progressTimer.wrappedValue?.invalidate()
                    progressTimer.wrappedValue = nil
                    progressValue.wrappedValue = 0.0
                }
                appState.addLog(level: .info, module: "camera", message: "Photo captured: \(Int(image.size.width))×\(Int(image.size.height))", controller: controller)
                
                // Refresh status and stream view after photo capture
                try await Task.sleep(nanoseconds: 1_500_000_000) // Wait 1.5 seconds for stream to restart
                controller.fetchStatus()
                
                // Force refresh stream view
                await MainActor.run {
                    streamRefreshID.wrappedValue = UUID()
                }
            } else {
                await MainActor.run {
                    active.wrappedValue = false
                    startTime.wrappedValue = ""
                    progressTimer.wrappedValue?.invalidate()
                    progressTimer.wrappedValue = nil
                    progressValue.wrappedValue = 0.0
                }
                appState.addLog(level: .error, module: "camera", message: "Failed to decode photo", controller: controller)
            }
        } catch {
            await MainActor.run {
                active.wrappedValue = false
                startTime.wrappedValue = ""
                progressTimer.wrappedValue?.invalidate()
                progressTimer.wrappedValue = nil
            }
            appState.addLog(level: .error, module: "camera", message: "Failed to capture photo: \(error.localizedDescription)", controller: controller)
        }
    }
}

private func selectSequenceSavePath(savePath: Binding<String>, bookmarkData: Binding<Data>) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.message = "Select folder to save sequence photos on this Mac"
    
    if panel.runModal() == .OK {
        if let url = panel.url {
            // Start accessing the resource immediately (NSOpenPanel grants temporary access)
            let accessing = url.startAccessingSecurityScopedResource()
            
            // Create security-scoped bookmark for persistent access
            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                bookmarkData.wrappedValue = bookmark
                savePath.wrappedValue = url.path
                print("✅ Created security-scoped bookmark for: \(url.path), accessing: \(accessing)")
            } catch {
                print("❌ Failed to create bookmark: \(error)")
                bookmarkData.wrappedValue = Data()
                savePath.wrappedValue = url.path
            }
            
            // Stop accessing (we'll use the bookmark later)
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
}

private func startSequence(controller: ControllerState, appState: AppState, savePath: Binding<String>, bookmarkData: Binding<Data>, count: Binding<Int>, fileFormat: Binding<String>, interval: Binding<Double>, active: Binding<Bool>, currentCount: Binding<Int>, totalCount: Binding<Int>, progressTimer: Binding<Timer?>, startTimeString: Binding<String>, gain: Binding<Double>, photoExposure: Binding<Double>) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { return }
            
            if savePath.wrappedValue.isEmpty {
                appState.addLog(level: .error, module: "camera", message: "Please select a save path first", controller: controller)
                return
            }
            
            // Resolve bookmark to get URL with security-scoped access
            var folderURL: URL?
            var isStale = false
            
            if !bookmarkData.wrappedValue.isEmpty {
                do {
                    folderURL = try URL(
                        resolvingBookmarkData: bookmarkData.wrappedValue,
                        options: [.withSecurityScope, .withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    if let resolvedURL = folderURL {
                        print("✅ Resolved bookmark to: \(resolvedURL.path)")
                    }
                    if isStale {
                        appState.addLog(level: .warn, module: "camera", message: "Bookmark is stale, please reselect folder", controller: controller)
                        print("⚠️ Bookmark is stale")
                    }
                } catch {
                    appState.addLog(level: .error, module: "camera", message: "Failed to resolve bookmark: \(error.localizedDescription)", controller: controller)
                    print("❌ Failed to resolve bookmark: \(error)")
                }
            } else {
                print("⚠️ No bookmark data, using path fallback")
            }
            
            // Fallback to path if bookmark resolution failed
            if folderURL == nil {
                folderURL = URL(fileURLWithPath: savePath.wrappedValue)
            }
            
            guard let folderURL = folderURL else {
                appState.addLog(level: .error, module: "camera", message: "Invalid save path", controller: controller)
                return
            }
            
            // Validate save path exists first
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                appState.addLog(level: .error, module: "camera", message: "Invalid save path: \(folderURL.path)", controller: controller)
                return
            }
            
            await MainActor.run {
                active.wrappedValue = true
                totalCount.wrappedValue = count.wrappedValue
                currentCount.wrappedValue = 0
            }
            
            appState.addLog(level: .info, module: "camera", message: "Starting sequence capture: \(count.wrappedValue) photos to \(savePath.wrappedValue)", controller: controller)
            
            // Capture all photos at once (simple: tell camera to take N photos)
            let total = count.wrappedValue
            let format = fileFormat.wrappedValue
            let currentGain = Int(gain.wrappedValue)
            let exposure = photoExposure.wrappedValue
            
            // Calculate estimated total time based on exposure and interval
            let intervalValue = interval.wrappedValue
            let estimatedTime: Double
            if intervalValue > 0 {
                // Time-lapse mode: (exposure + interval) * count
                // Each photo takes: exposure time + interval time
                estimatedTime = (exposure + intervalValue) * Double(total)
            } else {
                // Fast mode: exposure * count (no extra wait time)
                estimatedTime = exposure * Double(total)
            }
            
            let startTime = Date()
            await MainActor.run {
                startTimeString.wrappedValue = String(startTime.timeIntervalSince1970)
                totalCount.wrappedValue = total
                currentCount.wrappedValue = 0
                active.wrappedValue = true
            }
            
            // Start progress timer for smooth progress bar
            await MainActor.run {
                startSequenceProgressTimer(total: total, estimatedTime: estimatedTime, active: active, currentCount: currentCount, progressTimer: progressTimer, startTimeString: startTimeString)
            }
            
            // Start accessing security-scoped resource BEFORE saving files
            // Keep access for the entire save loop
            var accessing = false
            if !bookmarkData.wrappedValue.isEmpty {
                // Try to access using bookmark
                accessing = folderURL.startAccessingSecurityScopedResource()
                if !accessing {
                    appState.addLog(level: .error, module: "camera", message: "Failed to access security-scoped resource. Bookmark may be invalid. Please reselect folder.", controller: controller)
                    print("❌ Failed to start accessing security-scoped resource for: \(folderURL.path)")
                } else {
                    print("✅ Successfully started accessing security-scoped resource for: \(folderURL.path)")
                }
            } else {
                // No bookmark, try direct access (may not work due to sandbox)
                accessing = folderURL.startAccessingSecurityScopedResource()
                if !accessing {
                    appState.addLog(level: .error, module: "camera", message: "No bookmark available and direct access failed. Please select folder using Browse button.", controller: controller)
                    print("❌ No bookmark and direct access failed for: \(folderURL.path)")
                }
            }
            
            defer {
                if accessing {
                    folderURL.stopAccessingSecurityScopedResource()
                    print("🔒 Stopped accessing security-scoped resource")
                }
            }
            
            // If we couldn't get access, abort
            if !accessing {
                await MainActor.run {
                    active.wrappedValue = false
                    progressTimer.wrappedValue?.invalidate()
                    progressTimer.wrappedValue = nil
                    startTimeString.wrappedValue = ""
                    currentCount.wrappedValue = 0
                }
                return
            }
            
            // Save all photos
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let baseTimestamp = dateFormatter.string(from: Date())
            
            let fileExtension = format.lowercased() == "jpeg" ? "jpg" : format.lowercased()
            
            var savedCount = 0
            
            // Choose capture mode
            if intervalValue > 0 {
                // Time-lapse mode: capture one by one with interval
                appState.addLog(level: .info, module: "camera", message: "Starting time-lapse: \(total) photos with \(String(format: "%.1f", intervalValue))s interval (estimated time: \(String(format: "%.1f", estimatedTime))s)...", controller: controller)
                
                for index in 0..<total {
                    // Check if stopped by user
                    if !active.wrappedValue {
                        appState.addLog(level: .info, module: "camera", message: "Sequence stopped by user", controller: controller)
                        break
                    }
                    
                    // Capture single photo
                    appState.addLog(level: .info, module: "camera", message: "Capturing photo \(index + 1)/\(total)...", controller: controller)
                    let imageData = try await apiClient.captureSnapshot()
                    
                    guard let image = NSImage(data: imageData) else {
                        appState.addLog(level: .error, module: "camera", message: "Failed to decode photo \(index + 1)", controller: controller)
                        continue
                    }
                    
                    // Generate filename
                    let filename = "\(baseTimestamp)_seq\(String(format: "%04d", index + 1))of\(String(format: "%04d", total))_gain\(currentGain)_exp\(String(format: "%.3f", exposure))s.\(fileExtension)"
                    let fileURL = folderURL.appendingPathComponent(filename)
                    
                    // Convert and save image in desired format
                    guard let tiffData = image.tiffRepresentation,
                          let bitmapImage = NSBitmapImageRep(data: tiffData) else {
                        appState.addLog(level: .error, module: "camera", message: "Failed to convert photo \(index + 1) to bitmap", controller: controller)
                        continue
                    }
                    
                    var finalData: Data?
                    switch format.uppercased() {
                    case "JPEG":
                        finalData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
                    case "PNG":
                        finalData = bitmapImage.representation(using: .png, properties: [:])
                    case "TIFF":
                        finalData = bitmapImage.representation(using: .tiff, properties: [:])
                    default:
                        finalData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
                    }
                    
                    guard let data = finalData else {
                        appState.addLog(level: .error, module: "camera", message: "Failed to encode photo \(index + 1) as \(format)", controller: controller)
                        continue
                    }
                    
                    // Write file
                    do {
                        try data.write(to: fileURL, options: .atomic)
                        print("✅ Saved file: \(filename)")
                        savedCount += 1
                    } catch {
                        let nsError = error as NSError
                        appState.addLog(level: .error, module: "camera", message: "Failed to write file \(filename): \(error.localizedDescription)", controller: controller)
                        print("❌ Failed to write file: \(error), URL: \(fileURL.path)")
                        continue
                    }
                    
                    await MainActor.run {
                        currentCount.wrappedValue = index + 1
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Saved photo \(index + 1)/\(total): \(filename)", controller: controller)
                    
                    // Wait for interval before next photo (except for the last one)
                    if index < total - 1 && active.wrappedValue {
                        try await Task.sleep(nanoseconds: UInt64(intervalValue * 1_000_000_000))
                    }
                }
            } else {
                // Fast mode: use synchronous capture API
                appState.addLog(level: .info, module: "camera", message: "Capturing \(total) photos (estimated time: \(String(format: "%.1f", estimatedTime))s)...", controller: controller)
                
                let response = try await apiClient.captureSequence(count: total)
                
                // Debug: Log response details
                print("📸 [Sequence] Received \(response.photos.count) photos from server")
                for (idx, photo) in response.photos.enumerated() {
                    if photo == nil {
                        print("⚠️ [Sequence] Photo \(idx + 1) is nil")
                    } else {
                        print("✅ [Sequence] Photo \(idx + 1) has \(photo!.count) characters")
                    }
                }
                
                for (index, photoBase64) in response.photos.enumerated() {
                    // Check if stopped by user
                    if !active.wrappedValue {
                        appState.addLog(level: .info, module: "camera", message: "Sequence stopped by user", controller: controller)
                        break
                    }
                    
                    guard let photoBase64 = photoBase64 else {
                        appState.addLog(level: .error, module: "camera", message: "Photo \(index + 1) is nil", controller: controller)
                        continue
                    }
                    
                    // Clean base64 string (remove data URL prefix if present)
                    var cleanBase64 = photoBase64
                    if let commaIndex = cleanBase64.firstIndex(of: ",") {
                        cleanBase64 = String(cleanBase64[cleanBase64.index(after: commaIndex)...])
                    }
                    
                    guard let imageData = Data(base64Encoded: cleanBase64, options: .ignoreUnknownCharacters),
                          let image = NSImage(data: imageData) else {
                        appState.addLog(level: .error, module: "camera", message: "Failed to decode photo \(index + 1). Base64 length: \(photoBase64.count)", controller: controller)
                        continue
                    }
                    
                    // Generate filename
                    let filename = "\(baseTimestamp)_seq\(String(format: "%04d", index + 1))of\(String(format: "%04d", total))_gain\(currentGain)_exp\(String(format: "%.3f", exposure))s.\(fileExtension)"
                    let fileURL = folderURL.appendingPathComponent(filename)
                    
                    // Convert and save image in desired format
                    guard let tiffData = image.tiffRepresentation,
                          let bitmapImage = NSBitmapImageRep(data: tiffData) else {
                        appState.addLog(level: .error, module: "camera", message: "Failed to convert photo \(index + 1) to bitmap", controller: controller)
                        continue
                    }
                    
                    var finalData: Data?
                    switch format.uppercased() {
                    case "JPEG":
                        finalData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
                    case "PNG":
                        finalData = bitmapImage.representation(using: .png, properties: [:])
                    case "TIFF":
                        finalData = bitmapImage.representation(using: .tiff, properties: [:])
                    default:
                        finalData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 1.0])
                    }
                    
                    guard let data = finalData else {
                        appState.addLog(level: .error, module: "camera", message: "Failed to encode photo \(index + 1) as \(format)", controller: controller)
                        continue
                    }
                    
                    // Write file - security-scoped access for folder is already active
                    do {
                        try data.write(to: fileURL, options: .atomic)
                        print("✅ Saved file: \(filename)")
                        savedCount += 1
                    } catch {
                        let nsError = error as NSError
                        appState.addLog(level: .error, module: "camera", message: "Failed to write file \(filename): \(error.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))", controller: controller)
                        print("❌ Failed to write file: \(error), URL: \(fileURL.path)")
                        continue
                    }
                    
                    await MainActor.run {
                        currentCount.wrappedValue = index + 1
                    }
                    
                    appState.addLog(level: .info, module: "camera", message: "Saved photo \(index + 1)/\(total): \(filename)", controller: controller)
                }
                
                await MainActor.run {
                    progressTimer.wrappedValue?.invalidate()
                    progressTimer.wrappedValue = nil
                    startTimeString.wrappedValue = ""
                    // Set final count
                    currentCount.wrappedValue = savedCount
                    active.wrappedValue = false
                    if savedCount >= totalCount.wrappedValue {
                        appState.addLog(level: .info, module: "camera", message: "Sequence capture completed: \(savedCount)/\(total) photos", controller: controller)
                    }
                }
            }
            
        } catch {
            await MainActor.run {
                active.wrappedValue = false
                startTimeString.wrappedValue = ""
                progressTimer.wrappedValue?.invalidate()
                progressTimer.wrappedValue = nil
            }
            appState.addLog(level: .error, module: "camera", message: "Failed to capture sequence: \(error.localizedDescription)", controller: controller)
        }
    }
}

private func startSequenceStatusPolling(controller: ControllerState, appState: AppState, active: Binding<Bool>, currentCount: Binding<Int>, totalCount: Binding<Int>, statusTimer: Binding<Timer?>) {
    // Stop existing timer if any
    statusTimer.wrappedValue?.invalidate()
    
    // Create new timer
    let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak appState] _ in
        Task {
            do {
                guard let apiClient = controller.apiClient else { return }
                let status = try await apiClient.getSequenceStatus()
                
                await MainActor.run {
                    active.wrappedValue = status.active
                    currentCount.wrappedValue = status.currentCount
                    totalCount.wrappedValue = status.totalCount
                    
                    if !status.active {
                        // Sequence completed or stopped
                        statusTimer.wrappedValue?.invalidate()
                        statusTimer.wrappedValue = nil
                        
                        if status.currentCount >= status.totalCount {
                            appState?.addLog(level: .info, module: "camera", message: "Sequence capture completed: \(status.currentCount)/\(status.totalCount) photos", controller: controller)
                        }
                    }
                }
            } catch {
                // Ignore polling errors
            }
        }
    }
    
    statusTimer.wrappedValue = timer
    RunLoop.main.add(timer, forMode: .common)
}
