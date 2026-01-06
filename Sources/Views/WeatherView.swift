import SwiftUI

// Cloud coverage data point
struct CloudCoverageDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let percentage: Double
}

// Cloud coverage chart view
private struct CloudCoverageChart: View {
    let dataPoints: [CloudCoverageDataPoint]
    let height: CGFloat = 200
    
    private var sortedPoints: [CloudCoverageDataPoint] {
        dataPoints.sorted { $0.timestamp < $1.timestamp }
    }
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // Calculate time range: now - 2 hours to now + 2 hours
            let now = Date()
            let twoHours: TimeInterval = 2 * 60 * 60 // 2 hours in seconds
            let minTime = now.timeIntervalSince1970 - twoHours
            let maxTime = now.timeIntervalSince1970 + twoHours
            let timeRange = maxTime - minTime
            let sorted = sortedPoints
            
            // Grid dimensions
            let yAxisWidth: CGFloat = 40
            let xAxisHeight: CGFloat = 25
            let chartHeight = height
            let chartWidth: CGFloat = 600 // Will be adjusted by GeometryReader
            
            GeometryReader { geometry in
                let totalWidth = geometry.size.width * 0.95 // Reduce width to 95%
                let totalHeight = geometry.size.height
                let actualChartWidth = totalWidth - yAxisWidth
                let actualChartHeight = totalHeight - xAxisHeight
                
                ZStack(alignment: .topLeading) {
                    // Complete grid system - all in one coordinate space
                    
                    // Y-axis labels (left side)
                    ForEach(0...4, id: \.self) { i in
                        let percentage = 100 - (i * 25)
                        let y = actualChartHeight * CGFloat(i) / 4
                        Text("\(percentage)%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: yAxisWidth - 5, alignment: .trailing)
                            .offset(x: 0, y: y - 6) // -6 to center text vertically
                    }
                    
                    // Chart area (offset by yAxisWidth)
                    ZStack {
                        // Background grid lines
                        Path { path in
                            // Horizontal grid lines (0%, 25%, 50%, 75%, 100%)
                            for i in 0...4 {
                                let y = actualChartHeight * CGFloat(i) / 4
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: actualChartWidth, y: y))
                            }
                        }
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        
                        // Chart line (only if we have data)
                        if sorted.count > 1 {
                            Path { path in
                                for (index, point) in sorted.enumerated() {
                                    let x = CGFloat((point.timestamp.timeIntervalSince1970 - minTime) / timeRange) * actualChartWidth
                                    let y = actualChartHeight * (1.0 - CGFloat(point.percentage / 100.0))
                                    
                                    if index == 0 {
                                        path.move(to: CGPoint(x: x, y: y))
                                    } else {
                                        path.addLine(to: CGPoint(x: x, y: y))
                                    }
                                }
                            }
                            .stroke(Color.blue, lineWidth: 2)
                            
                            // Data points
                            ForEach(sorted) { point in
                                let x = CGFloat((point.timestamp.timeIntervalSince1970 - minTime) / timeRange) * actualChartWidth
                                let y = actualChartHeight * (1.0 - CGFloat(point.percentage / 100.0))
                                
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 4, height: 4)
                                    .offset(x: x, y: y)
                            }
                        }
                    }
                    .offset(x: yAxisWidth, y: 0)
                    
                    // X-axis labels (bottom, offset by yAxisWidth)
                    let timeLabels: [(offset: TimeInterval, label: String)] = [
                        (-2 * 60 * 60, "-2h"),
                        (-1 * 60 * 60, "-1h"),
                        (0, "now"),
                        (1 * 60 * 60, "+1h"),
                        (2 * 60 * 60, "+2h")
                    ]
                    
                    ForEach(Array(timeLabels.enumerated()), id: \.offset) { index, timeLabel in
                        let timePoint = now.timeIntervalSince1970 + timeLabel.offset
                        let x = CGFloat((timePoint - minTime) / timeRange) * actualChartWidth
                        Text(timeLabel.label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .offset(x: x + yAxisWidth, y: actualChartHeight + 5)
                    }
                }
            }
            .frame(height: height + 25) // chart height + x-axis height
            .frame(maxWidth: .infinity) // Center the chart horizontally
            .offset(x: 10, y: 10) // Move slightly right and down
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct WeatherView: View {
    @EnvironmentObject private var appState: AppState
    @State private var cloudCoverageData: [CloudCoverageDataPoint] = []
    
    private var weather: WeatherModel { appState.weather }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricsGrid
                
                // Cloud Coverage Section
                cloudCoverageHeader
                CloudCoverageChart(dataPoints: cloudCoverageData)
                
                if let time = weather.observationTime {
                    Text("Last updated \(time.formatted(date: .omitted, time: .standard))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Weather – Pomfret, CT")
                .font(.largeTitle.bold())
            Text("Powered by Open‑Meteo")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var cloudCoverageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cloud Coverage Exact")
                .font(.largeTitle.bold())
            Text("Powered by Pomfret All Sky Cam and Detection Algorithm")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var metricsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3), spacing: 16) {
            WeatherCard(title: "Temperature", value: value(weather.temperatureC, suffix: "°C"), icon: "thermometer")
            WeatherCard(title: "Apparent Temperature", value: value(weather.apparentTemperatureC, suffix: "°C"), icon: "thermometer.medium")
            WeatherCard(title: "Humidity", value: value(weather.humidityPercent, suffix: "%"), icon: "humidity")
            WeatherCard(title: "Cloud Cover", value: value(weather.cloudCoverPercent, suffix: "%"), icon: "cloud.fill")
            WeatherCard(title: "Wind Speed", value: value(weather.windSpeed, suffix: " km/h"), icon: "wind")
            WeatherCard(title: "Wind Gust", value: value(weather.windGust, suffix: " km/h"), icon: "tornado")
        }
    }
    
    private func value(_ number: Double?, suffix: String) -> String {
        guard let number else { return "—" }
        if suffix.contains("%") {
            return String(format: "%.0f%@", number, suffix)
        } else if suffix.contains("km") || suffix.contains("mm") {
            return String(format: "%.0f%@", number, suffix)
        } else {
            return String(format: "%.1f%@", number, suffix)
        }
    }
}

private struct WeatherCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

