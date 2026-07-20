import Foundation
import CoreLocation
import SwiftUI

struct Trail: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let distanceMiles: Double
    let elevationGainFeet: Double
    let highestPointFeet: Double
    let difficulty: Int
    let durationMinutes: Double
    let routeType: String
    let rating: Double
    let reviewCount: Int
    let area: String
    let state: String
    let country: String
    let latitude: Double
    let longitude: Double
    let url: String
    let photoURL: String
}

extension Trail {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceKm: Double { distanceMiles * 1.60934 }
    var elevationGainMeters: Double { elevationGainFeet * 0.3048 }
    var highestPointMeters: Double { highestPointFeet * 0.3048 }

    var difficultyLabel: String {
        switch difficulty {
        case ..<3: return "简单"
        case 3..<5: return "中等"
        case 5..<7: return "困难"
        default: return "极难"
        }
    }

    /// AllTrails 风格难度色：简单绿 / 中等蓝 / 困难近黑 / 极难红
    var difficultyColor: Color {
        switch difficulty {
        case ..<3: return .trailGreen
        case 3..<5: return Color(red: 0.24, green: 0.42, blue: 0.87)
        case 5..<7: return Color(red: 0.20, green: 0.20, blue: 0.22)
        default: return Color(red: 0.80, green: 0.25, blue: 0.22)
        }
    }

    var formattedDistance: String { String(format: "%.1f km", distanceKm) }

    var formattedGain: String {
        elevationGainMeters > 0 ? String(format: "%.0f m", elevationGainMeters) : "—"
    }

    var formattedHighestPoint: String {
        highestPointMeters > 0 ? String(format: "%.0f m", highestPointMeters) : "—"
    }

    var formattedDuration: String {
        guard durationMinutes > 0 else { return "—" }
        let h = Int(durationMinutes) / 60
        let m = Int(durationMinutes) % 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }

    var formattedReviews: String {
        reviewCount >= 1000
            ? String(format: "%.1fk", Double(reviewCount) / 1000)
            : "\(reviewCount)"
    }

    var routeTypeLabel: String {
        switch routeType.lowercased() {
        case "loop": return "环线"
        case "out & back": return "往返"
        case "point to point": return "单程"
        default: return routeType
        }
    }

    var locationLine: String { area.isEmpty ? state : "\(area) · \(state)" }
    var webURL: URL? { URL(string: url) }
    var coverURL: URL? { photoURL.isEmpty ? nil : URL(string: photoURL) }
}

struct TrailFilter: Equatable {
    var difficulties: Set<Int> = []   // 空 = 全部；取值 1/3/5/7
    var minRating: Double = 0         // 0 = 不限
    var lengthBucket: LengthBucket = .any
    var state: String? = nil

    enum LengthBucket: String, CaseIterable, Identifiable {
        case any = "不限"
        case short = "<5 km"
        case medium = "5–15 km"
        case long = ">15 km"

        var id: String { rawValue }

        /// 长度区间，单位英里（数据库中 distance 为英里）
        var rangeMiles: (Double, Double)? {
            switch self {
            case .any: return nil
            case .short: return (0, 3.107)
            case .medium: return (3.107, 9.321)
            case .long: return (9.321, 100000)
            }
        }
    }

    var isActive: Bool {
        !difficulties.isEmpty || minRating > 0 || lengthBucket != .any || state != nil
    }
}
