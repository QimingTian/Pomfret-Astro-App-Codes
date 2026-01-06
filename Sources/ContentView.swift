import SwiftUI

struct ContentView: View {
	@EnvironmentObject var appState: AppState

	var body: some View {
		NavigationSplitView {
			List(selection: $appState.selection) {
				NavigationLink(value: AppSection.sensors) {
					Label("Camera", systemImage: "camera")
				}
				NavigationLink(value: AppSection.weather) {
					Label("Weather", systemImage: "cloud.sun")
				}
				NavigationLink(value: AppSection.calendar) {
					Label("Calendar", systemImage: "calendar")
				}
				NavigationLink(value: AppSection.logs) {
					Label("Logs", systemImage: "list.bullet.rectangle")
				}
				NavigationLink(value: AppSection.settings) {
					Label("Settings", systemImage: "gearshape")
				}
			}
			.listStyle(.sidebar)
		} detail: {
			switch appState.selection {
			case .sensors: SensorsView()
			case .weather: WeatherView()
			case .calendar: CalendarView()
			case .logs: LogsView()
			case .settings: SettingsView()
			}
		}
	}
}

enum AppSection: Hashable {
	case sensors, weather, calendar, logs, settings
}

