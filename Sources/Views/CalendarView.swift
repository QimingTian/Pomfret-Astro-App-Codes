import SwiftUI

struct CalendarView: View {
    @EnvironmentObject var appState: AppState
    @State private var bookings: [Booking] = []
    @State private var selectedDate = Date()
    @State private var showingAddBooking = false
    @State private var showingBookingDetail: Booking?
    @State private var isLoading = false
    @State private var lastRefreshTime: Date?
    @State private var refreshTimer: Timer?
    
    private let calendar = Calendar.current
    
    private var controller: ControllerState? {
        appState.camerasController
    }
    
    private var isConnected: Bool {
        guard let controller = controller else { return false }
        return appState.connectedControllers.contains(controller.id)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                
                // Calendar month view
                monthView
                
                // Bookings list for selected date
                bookingsList
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAddBooking) {
            AddBookingView(selectedDate: selectedDate) { booking in
                addBooking(booking)
            }
        }
        .sheet(item: $showingBookingDetail) { booking in
            BookingDetailView(booking: booking) { updatedBooking in
                updateBooking(updatedBooking)
            } onDelete: {
                deleteBooking(booking)
            }
        }
        .onAppear {
            loadBookings()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Camera Booking Calendar")
                .font(.largeTitle.bold())
            Text("Reserve time slots for camera control")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var monthView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Month header with navigation
            HStack {
                Button(action: { changeMonth(-1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(monthYearString)
                    .font(.title2.bold())
                
                Spacer()
                
                Button(action: { changeMonth(1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(calendarDays, id: \.self) { date in
                    if let date = date {
                        CalendarDayView(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasBookings: hasBookings(on: date),
                            onSelect: { selectedDate = date }
                        )
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
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
    
    private var bookingsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bookings for \(selectedDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.headline)
                    if isConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Online")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let lastRefresh = lastRefreshTime {
                                Text("• Updated \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 6, height: 6)
                            Text("Offline (local only)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Button(action: { showingAddBooking = true }) {
                    Label("Add Booking", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isConnected)
            }
            
            let dayBookings = bookingsForDate(selectedDate)
            if dayBookings.isEmpty {
                Text("No bookings for this date")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(dayBookings.sorted(by: { $0.startTime < $1.startTime })) { booking in
                    BookingRowView(booking: booking) {
                        showingBookingDetail = booking
                    }
                }
            }
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
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }
    
    private var calendarDays: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: selectedDate),
              let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let daysInMonth = calendar.range(of: .day, in: .month, for: selectedDate)?.count ?? 0
        
        var days: [Date?] = []
        
        // Add empty cells for days before the first day of the month
        for _ in 1..<firstWeekday {
            days.append(nil)
        }
        
        // Add all days in the month
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private func changeMonth(_ direction: Int) {
        if let newDate = calendar.date(byAdding: .month, value: direction, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func hasBookings(on date: Date) -> Bool {
        bookings.contains { booking in
            calendar.isDate(booking.startTime, inSameDayAs: date) ||
            calendar.isDate(booking.endTime, inSameDayAs: date) ||
            (booking.startTime <= date && booking.endTime >= date)
        }
    }
    
    private func bookingsForDate(_ date: Date) -> [Booking] {
        bookings.filter { booking in
            calendar.isDate(booking.startTime, inSameDayAs: date) ||
            calendar.isDate(booking.endTime, inSameDayAs: date) ||
            (booking.startTime <= date && booking.endTime >= date)
        }
    }
    
    private func addBooking(_ booking: Booking) {
        guard let controller = controller, let apiClient = controller.apiClient, isConnected else {
            // Fallback to local storage if not connected
            bookings.append(booking)
            saveBookingsLocally()
            appState.addLog(level: .warn, module: "calendar", message: "Not connected to server, saved locally only")
            return
        }
        
        Task {
            do {
                let request = BookingRequest(
                    userName: booking.userName,
                    startTime: booking.startTime,
                    endTime: booking.endTime,
                    notes: booking.notes
                )
                let response = try await apiClient.createBooking(request)
                
                // Convert response to Booking
                let newBooking = Booking(from: response)
                
                await MainActor.run {
                    bookings.append(newBooking)
                    lastRefreshTime = Date()
                    appState.addLog(level: .info, module: "calendar", message: "Added booking: \(newBooking.userName)")
                }
            } catch {
                await MainActor.run {
                    appState.addLog(level: .error, module: "calendar", message: "Failed to add booking: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func updateBooking(_ booking: Booking) {
        guard let controller = controller, let apiClient = controller.apiClient, isConnected else {
            // Fallback to local storage if not connected
            if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
                bookings[index] = booking
                saveBookingsLocally()
                appState.addLog(level: .warn, module: "calendar", message: "Not connected to server, saved locally only")
            }
            return
        }
        
        Task {
            do {
                let bookingId = booking.id.uuidString
                let request = BookingRequest(
                    userName: booking.userName,
                    startTime: booking.startTime,
                    endTime: booking.endTime,
                    notes: booking.notes
                )
                let response = try await apiClient.updateBooking(id: bookingId, booking: request)
                
                // Convert response to Booking
                let updatedBooking = Booking(from: response)
                
                await MainActor.run {
                    if let index = bookings.firstIndex(where: { $0.id == booking.id }) {
                        bookings[index] = updatedBooking
                    }
                    lastRefreshTime = Date()
                    appState.addLog(level: .info, module: "calendar", message: "Updated booking: \(updatedBooking.userName)")
                }
            } catch {
                await MainActor.run {
                    appState.addLog(level: .error, module: "calendar", message: "Failed to update booking: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func deleteBooking(_ booking: Booking) {
        guard let controller = controller, let apiClient = controller.apiClient, isConnected else {
            // Fallback to local storage if not connected
            bookings.removeAll { $0.id == booking.id }
            saveBookingsLocally()
            appState.addLog(level: .warn, module: "calendar", message: "Not connected to server, deleted locally only")
            return
        }
        
        Task {
            do {
                let bookingId = booking.id.uuidString
                try await apiClient.deleteBooking(id: bookingId)
                
                await MainActor.run {
                    bookings.removeAll { $0.id == booking.id }
                    lastRefreshTime = Date()
                    appState.addLog(level: .info, module: "calendar", message: "Deleted booking: \(booking.userName)")
                }
            } catch {
                await MainActor.run {
                    appState.addLog(level: .error, module: "calendar", message: "Failed to delete booking: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func loadBookings() {
        guard let controller = controller, let apiClient = controller.apiClient, isConnected else {
            // Fallback to local storage
            loadBookingsLocally()
            return
        }
        
        Task {
            await MainActor.run {
                isLoading = true
            }
            
            do {
                let responses = try await apiClient.fetchBookings()
                
                // Convert BookingResponse to Booking
                let loadedBookings = responses.map { Booking(from: $0) }
                
                await MainActor.run {
                    bookings = loadedBookings
                    isLoading = false
                    lastRefreshTime = Date()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Fallback to local storage on error
                    loadBookingsLocally()
                    appState.addLog(level: .warn, module: "calendar", message: "Failed to load bookings from server, using local data: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak appState] _ in
            Task { @MainActor in
                guard let appState = appState,
                      let controller = appState.camerasController,
                      appState.connectedControllers.contains(controller.id) else {
                    return
                }
                // Reload bookings from server
                loadBookings()
            }
        }
    }
    
    // Local storage fallback methods
    private func loadBookingsLocally() {
        if let data = UserDefaults.standard.data(forKey: "observatory.bookings"),
           let decoded = try? JSONDecoder().decode([Booking].self, from: data) {
            bookings = decoded
        }
    }
    
    private func saveBookingsLocally() {
        if let encoded = try? JSONEncoder().encode(bookings) {
            UserDefaults.standard.set(encoded, forKey: "observatory.bookings")
        }
    }
}

// Calendar Day View
private struct CalendarDayView: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasBookings: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 14, weight: isToday ? .bold : .regular))
                    .foregroundColor(isSelected ? .white : (isToday ? .blue : .primary))
                
                if hasBookings {
                    Circle()
                        .fill(isSelected ? .white : .blue)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue : (isHovered ? Color.blue.opacity(0.1) : Color.clear))
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// Booking Row View
private struct BookingRowView: View {
    let booking: Booking
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(booking.userName)
                        .font(.headline)
                    HStack {
                        Text(booking.startTime.formatted(date: .omitted, time: .shortened))
                        Text("–")
                            .foregroundColor(.secondary)
                        Text(booking.endTime.formatted(date: .omitted, time: .shortened))
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    if let notes = booking.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }
}

// Add Booking View
private struct AddBookingView: View {
    @Environment(\.dismiss) var dismiss
    let selectedDate: Date
    let onSave: (Booking) -> Void
    
    @State private var userName: String = ""
    @State private var startDateString: String = ""
    @State private var endDateString: String = ""
    @State private var notes: String = ""
    @State private var startDateError: String?
    @State private var endDateError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Booking")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // User Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Information")
                            .font(.headline)
                        TextField("Your Name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Time Slot
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time Slot")
                            .font(.headline)
                        Text("Format: YYYY-MM-DD HH:MM (e.g., 2024-12-25 14:30) or MM/DD/YYYY HH:MM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start Time")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("YYYY-MM-DD HH:MM", text: $startDateString)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: startDateString) { _ in
                                        startDateError = nil
                                    }
                                if let error = startDateError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End Time")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("YYYY-MM-DD HH:MM", text: $endDateString)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: endDateString) { _ in
                                        endDateError = nil
                                    }
                                if let error = endDateError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.headline)
                        TextField("Add notes...", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Save") {
                    if let startDate = parseDateTime(startDateString),
                       let endDate = parseDateTime(endDateString) {
                        if endDate > startDate {
                            let booking = Booking(
                                userName: userName,
                                startTime: startDate,
                                endTime: endDate,
                                notes: notes.isEmpty ? nil : notes
                            )
                            onSave(booking)
                            dismiss()
                        } else {
                            endDateError = "End time must be after start time"
                        }
                    } else {
                        if parseDateTime(startDateString) == nil {
                            startDateError = "Invalid date format"
                        }
                        if parseDateTime(endDateString) == nil {
                            endDateError = "Invalid date format"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userName.isEmpty || startDateString.isEmpty || endDateString.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 550, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Set default start time to selected date at current hour
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            let minute = calendar.component(.minute, from: Date())
            if let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                startDateString = formatter.string(from: date)
                endDateString = formatter.string(from: date.addingTimeInterval(3600))
            }
        }
    }
    
    private func parseDateTime(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd/MM/yyyy HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd HH:mm"
                f.defaultDate = selectedDate
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd/MM HH:mm"
                f.defaultDate = selectedDate
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        
        return nil
    }
}

// Booking Detail View
private struct BookingDetailView: View {
    @Environment(\.dismiss) var dismiss
    let booking: Booking
    let onUpdate: (Booking) -> Void
    let onDelete: () -> Void
    
    @State private var userName: String
    @State private var startDateString: String
    @State private var endDateString: String
    @State private var notes: String
    @State private var startDateError: String?
    @State private var endDateError: String?
    
    init(booking: Booking, onUpdate: @escaping (Booking) -> Void, onDelete: @escaping () -> Void) {
        self.booking = booking
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        _userName = State(initialValue: booking.userName)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        _startDateString = State(initialValue: formatter.string(from: booking.startTime))
        _endDateString = State(initialValue: formatter.string(from: booking.endTime))
        _notes = State(initialValue: booking.notes ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Booking")
                    .font(.title2.bold())
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // User Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Information")
                            .font(.headline)
                        TextField("Your Name", text: $userName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Time Slot
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time Slot")
                            .font(.headline)
                        Text("Format: YYYY-MM-DD HH:MM (e.g., 2024-12-25 14:30) or MM/DD/YYYY HH:MM")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start Time")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("YYYY-MM-DD HH:MM", text: $startDateString)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: startDateString) { _ in
                                        startDateError = nil
                                    }
                                if let error = startDateError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End Time")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextField("YYYY-MM-DD HH:MM", text: $endDateString)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: endDateString) { _ in
                                        endDateError = nil
                                    }
                                if let error = endDateError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes (Optional)")
                            .font(.headline)
                        TextField("Add notes...", text: $notes)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    if let startDate = parseDateTime(startDateString),
                       let endDate = parseDateTime(endDateString) {
                        if endDate > startDate {
                            let updated = Booking(
                                id: booking.id,
                                userName: userName,
                                startTime: startDate,
                                endTime: endDate,
                                notes: notes.isEmpty ? nil : notes
                            )
                            onUpdate(updated)
                            dismiss()
                        } else {
                            endDateError = "End time must be after start time"
                        }
                    } else {
                        if parseDateTime(startDateString) == nil {
                            startDateError = "Invalid date format"
                        }
                        if parseDateTime(endDateString) == nil {
                            endDateError = "Invalid date format"
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(userName.isEmpty || startDateString.isEmpty || endDateString.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 550, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func parseDateTime(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy/MM/dd HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd/MM/yyyy HH:mm"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd HH:mm"
                f.defaultDate = booking.startTime
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "dd/MM HH:mm"
                f.defaultDate = booking.startTime
                return f
            }()
        ]
        
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        
        return nil
    }
}

