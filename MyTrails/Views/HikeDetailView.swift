import SwiftUI
import MapKit
import CoreLocation

/// 单次徒步记录详情：GPS 路线图 + 统计。
struct HikeDetailView: View {
    let hike: HikeRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let track = hike.track, track.count > 1 {
                    routeMap(track)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color.trailGreen, Color.trailDark],
                                       startPoint: .top, endPoint: .bottom)
                        Text("此记录没有 GPS 轨迹")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .frame(height: 140)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(hike.trailName)
                        .font(.title2.bold())
                    if !hike.state.isEmpty {
                        Text(hike.state)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let rating = hike.rating, rating > 0 {
                        HStack(spacing: 6) {
                            StarDisplay(rating: rating, size: .subheadline)
                            Text("我的评分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatCell(title: "距离", value: String(format: "%.2f km", hike.distanceKm),
                             icon: "point.topleft.down.to.point.bottomright.curvepath")
                    StatCell(title: "用时", value: hike.formattedDuration, icon: "clock")
                    StatCell(title: "日期", value: hike.date.formatted(date: .abbreviated, time: .omitted),
                             icon: "calendar")
                    StatCell(title: "轨迹点", value: "\(hike.track?.count ?? 0)", icon: "point.3.connected.trianglepath.dotted")
                }
                .padding(.horizontal)

                if !hike.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("测评")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(hike.notes)
                            .font(.subheadline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                Spacer(minLength: 16)
            }
        }
        .navigationTitle("徒步详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func routeMap(_ track: [TrackPoint]) -> some View {
        let coords = track.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let lats = track.map(\.lat)
        let lngs = track.map(\.lng)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.5, 0.004),
            longitudeDelta: max((lngs.max()! - lngs.min()!) * 1.5, 0.004))

        return Map(initialPosition: .region(MKCoordinateRegion(center: center, span: span))) {
            MapPolyline(coordinates: coords)
                .stroke(Color.trailGreen, lineWidth: 4)
            Annotation("起点", coordinate: coords.first!) {
                Circle().fill(.green)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            Annotation("终点", coordinate: coords.last!) {
                Circle().fill(.red)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
        .frame(height: 280)
        .allowsHitTesting(false)
    }
}
