import Foundation

/// 轨迹点（精简存储，供 iCloud 同步）
struct TrackPoint: Codable, Hashable, Sendable {
    var lat: Double
    var lng: Double
}

/// 一次徒步记录（含 GPS 轨迹）
struct HikeRecord: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var trailId: String?
    var trailName: String
    var state: String
    var distanceMiles: Double
    var date: Date
    var durationMinutes: Int
    var notes: String
    var track: [TrackPoint]? = nil
    var rating: Int? = nil     // 1–5 星，nil/0 = 未评分
    var updatedAt = Date()
}

extension HikeRecord {
    var distanceKm: Double { distanceMiles * 1.60934 }

    var formattedDuration: String {
        guard durationMinutes > 0 else { return "—" }
        let h = durationMinutes / 60
        let m = durationMinutes % 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }

    var hasTrack: Bool { (track?.count ?? 0) > 1 }
}
