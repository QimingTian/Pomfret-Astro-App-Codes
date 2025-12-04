import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SensorsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Environment sensors (from sensors controller)
                if let controller = appState.sensorsController {
                    EnvironmentSection(controller: controller)
                }
                
                // Cameras (from cameras or sensors controller)
                if let cameraController = appState.camerasController ?? appState.sensorsController {
                    CombinedCameraSection(controller: cameraController)
                }
                
                // Show message if nothing is configured
                if appState.sensorsController == nil && appState.camerasController == nil {
                    MissingSensorsControllerCard()
                }
            }
            .padding()
        }
    }
}

private struct EnvironmentSection: View {
    @ObservedObject var controller: ControllerState
    
    var hasEnvironmentSensors: Bool {
        controller.sensors.temperature != nil || controller.sensors.humidity != nil
    }
    
    var body: some View {
        SensorsPanel(title: "Environment Sensors", icon: "thermometer") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StatusBadge(
                        text: hasEnvironmentSensors ? "Connected" : "Not Connected",
                        status: hasEnvironmentSensors ? .ok : .error
                    )
                }
                
                if hasEnvironmentSensors {
                    HStack(spacing: 24) {
                        if let temp = controller.sensors.temperature {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Temperature").font(.caption).foregroundColor(.secondary)
                                Text("\(temp, specifier: "%.1f")°C").font(.title2).foregroundColor(.blue)
                            }
                        }
                        if let hum = controller.sensors.humidity {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Humidity").font(.caption).foregroundColor(.secondary)
                                Text("\(hum, specifier: "%.0f")%").font(.title2).foregroundColor(.blue)
                            }
                        }
                    }
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .cornerRadius(8)
                        .overlay {
                            VStack(spacing: 8) {
                                if let temp = controller.sensors.temperature {
                                    Text("\(temp, specifier: "%.1f")°C").font(.largeTitle).foregroundColor(.blue)
                                }
                                if let hum = controller.sensors.humidity {
                                    Text("\(hum, specifier: "%.0f")% Humidity").font(.title3).foregroundColor(.secondary)
                                }
                            }
                        }
                } else {
                    Text("No environment sensors connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
        }
    }
}

private struct CombinedCameraSection: View {
    @ObservedObject var controller: ControllerState
    @EnvironmentObject var appState: AppState
    @AppStorage("camera.gain") private var gain: Double = 50
    @AppStorage("camera.streamExposure") private var exposure: Double = 0.1  // seconds - for stream
    @AppStorage("camera.photoExposure") private var photoExposure: Double = 1.0  // seconds - for photo capture
    @State private var capturedImage: NSImage?
    @State private var showingPhotoViewer = false
    
    var body: some View {
        cameraCard(
            title: "Weather & Meteor Monitor Camera",
            primaryCamera: controller.sensors.weatherCam,
            secondaryCamera: controller.sensors.meteorCam,
            controller: controller,
            appState: appState,
            gain: $gain,
            exposure: $exposure,
            photoExposure: $photoExposure,
            capturedImage: $capturedImage,
            showingPhotoViewer: $showingPhotoViewer
        )
        .sheet(isPresented: $showingPhotoViewer) {
            if let image = capturedImage {
                PhotoViewerSheet(image: image)
            }
        }
    }
}

@ViewBuilder
private func cameraCard(title: String, primaryCamera: SensorsModel.Camera, secondaryCamera: SensorsModel.Camera, controller: ControllerState, appState: AppState, gain: Binding<Double>, exposure: Binding<Double>, photoExposure: Binding<Double>, capturedImage: Binding<NSImage?>, showingPhotoViewer: Binding<Bool>) -> some View {
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
                    Slider(value: gain, in: 0...100, step: 1)
                    Text("\(Int(gain.wrappedValue))")
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                    Button("Set") {
                        updateCameraSetting(controller: controller, gain: Int(gain.wrappedValue), appState: appState)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Stream Exp:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: exposure, in: 0.001...1.0, step: 0.001)
                    Text(String(format: "%.3f s", exposure.wrappedValue))
                        .frame(width: 70, alignment: .trailing)
                        .monospacedDigit()
                    Button("Set") {
                        updateCameraSetting(controller: controller, streamExposure: exposure.wrappedValue, appState: appState)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                HStack {
                    Text("Photo Exp:")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: photoExposure, in: 0.001...10.0, step: 0.001)
                    Text(String(format: "%.3f s", photoExposure.wrappedValue))
                        .frame(width: 70, alignment: .trailing)
                        .monospacedDigit()
                    Button("Set") {
                        updateCameraSetting(controller: controller, photoExposure: photoExposure.wrappedValue, appState: appState)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
                    capturePhoto(controller: controller, appState: appState, capturedImage: capturedImage, showingPhotoViewer: showingPhotoViewer)
                }) {
                    Label("Capture Photo", systemImage: "camera")
                }
                .disabled(!isControllerConnected || !primaryCamera.connected)
                .buttonStyle(.borderedProminent)
            }
            if primaryCamera.streaming {
                ZStack {
                    MJPEGStreamView(url: "\(controller.baseURL)/camera/stream")
                        .frame(height: 500)
                    
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

private func capturePhoto(controller: ControllerState, appState: AppState, capturedImage: Binding<NSImage?>, showingPhotoViewer: Binding<Bool>) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { return }
            appState.addLog(level: .info, module: "camera", message: "Capturing photo...", controller: controller)
            
            let imageData = try await apiClient.captureSnapshot()
            
            if let image = NSImage(data: imageData) {
                await MainActor.run {
                    capturedImage.wrappedValue = image
                    showingPhotoViewer.wrappedValue = true
                }
                appState.addLog(level: .info, module: "camera", message: "Photo captured: \(Int(image.size.width))×\(Int(image.size.height))", controller: controller)
            } else {
                appState.addLog(level: .error, module: "camera", message: "Failed to decode photo", controller: controller)
            }
        } catch {
            appState.addLog(level: .error, module: "camera", message: "Failed to capture photo: \(error.localizedDescription)", controller: controller)
        }
    }
}

private func updateCameraSetting(controller: ControllerState, gain: Int? = nil, streamExposure: Double? = nil, photoExposure: Double? = nil, appState: AppState) {
    Task {
        do {
            guard let apiClient = controller.apiClient else { 
                appState.addLog(level: .error, module: "camera", message: "API client not available", controller: controller)
                return
            }
            
            var streamExpMicroseconds: Int?
            var photoExpMicroseconds: Int?
            
            if let exp = streamExposure {
                streamExpMicroseconds = Int(exp * 1_000_000)
                appState.addLog(level: .info, module: "camera", message: String(format: "Sending stream exposure: %.3f s", exp), controller: controller)
            }
            
            if let exp = photoExposure {
                photoExpMicroseconds = Int(exp * 1_000_000)
                appState.addLog(level: .info, module: "camera", message: String(format: "Sending photo exposure: %.3f s", exp), controller: controller)
            }
            
            if let g = gain {
                appState.addLog(level: .info, module: "camera", message: "Sending gain: \(g)", controller: controller)
            }
            
            try await apiClient.updateCameraSettings(gain: gain, streamExposure: streamExpMicroseconds, photoExposure: photoExpMicroseconds)
            
            if let g = gain {
                appState.addLog(level: .info, module: "camera", message: "✓ Gain set to \(g)", controller: controller)
            }
            if let exp = streamExposure {
                appState.addLog(level: .info, module: "camera", message: String(format: "✓ Stream exposure set to %.3f s", exp), controller: controller)
            }
            if let exp = photoExposure {
                appState.addLog(level: .info, module: "camera", message: String(format: "✓ Photo exposure set to %.3f s", exp), controller: controller)
            }
        } catch {
            appState.addLog(level: .error, module: "camera", message: "Failed to update settings: \(error.localizedDescription)", controller: controller)
        }
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

// Simple photo viewer sheet
private struct PhotoViewerSheet: View {
    let image: NSImage
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Captured Photo")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
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
            
            HStack {
                Text("Size: \(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 800, height: 700)
    }
}


