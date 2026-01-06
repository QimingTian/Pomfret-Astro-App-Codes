import Foundation

struct Booking: Identifiable, Codable {
    let id: UUID
    var userName: String
    var startTime: Date
    var endTime: Date
    var notes: String?
    
    init(id: UUID = UUID(), userName: String, startTime: Date, endTime: Date, notes: String? = nil) {
        self.id = id
        self.userName = userName
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
    }
    
    init(from response: BookingResponse) {
        self.id = UUID(uuidString: response.id) ?? UUID()
        self.userName = response.userName
        self.startTime = response.startTime
        self.endTime = response.endTime
        self.notes = response.notes
    }
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    func overlaps(with other: Booking) -> Bool {
        startTime < other.endTime && endTime > other.startTime
    }
}

