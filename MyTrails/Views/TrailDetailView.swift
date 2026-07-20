import SwiftUI
import MapKit

struct TrailDetailView: View {
    @EnvironmentObject private var store: DataStore
    let trail: Trail

    @State private var showRecorder = false
    @State private var routeSegments: [[CLLocationCoordinate2D]] = []

    private var isFavorite: Bool { store.favorites.contains(trail.id) }
    private var hikeCount: Int { store.hikeCount(for: trail.id) }
    private var myRating: Int? {
        store.hikes.first { $0.trailId == trail.id && ($0.rating ?? 0) > 0 }?.rating
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                cover

                VStack(alignment: .leading, spacing: 8) {
                    Text(trail.name)
                        .font(.title2.bold())
                    Text(trail.locationLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        DifficultyBadge(trail: trail)
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", trail.rating))
                            .font(.subheadline.bold())
                        Text("· \(trail.formattedReviews) 条评价")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !trail.routeType.isEmpty {
                            Text("· \(trail.routeTypeLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                statsGrid
                    .padding(.horizontal)

                miniMap
                    .padding(.horizontal)

                Button {
                    showRecorder = true
                } label: {
                    Label("开始 GPS 记录", systemImage: "record.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Color.trailGreen, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if hikeCount > 0 {
                    HStack(spacing: 10) {
                        Label("已记录 \(hikeCount) 次徒步", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(Color.trailGreen)
                        if let myRating {
                            HStack(spacing: 4) {
                                Text("我的评分")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                StarDisplay(rating: myRating)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Text("数据快照：\(DataStore.datasetDate) · 来源 AllTrails")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showRecorder) {
            RecordingView(trail: trail)
        }
        .task {
            // 调试钩子：MT_RECORD_TRAIL=1 打开详情页时自动进入录制界面
            if ProcessInfo.processInfo.environment["MT_RECORD_TRAIL"] != nil {
                showRecorder = true
            }
            routeSegments = await TrailPathLoader.paths(around: trail, db: store.db).matched
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.toggleFavorite(trail.id)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .primary)
                }
            }
        }
    }

    private var cover: some View {
        AsyncImage(url: trail.coverURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color.trailGreen.opacity(0.5), Color.trailGreen],
                               startPoint: .top, endPoint: .bottom)
                    .overlay {
                        Image(systemName: "figure.hiking")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(height: 220)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatCell(title: "距离", value: trail.formattedDistance, icon: "point.topleft.down.to.point.bottomright.curvepath")
            StatCell(title: "累计爬升", value: trail.formattedGain, icon: "arrow.up.right")
            StatCell(title: "最高点", value: trail.formattedHighestPoint, icon: "mountain.2")
            StatCell(title: "预计时长", value: trail.formattedDuration, icon: "clock")
        }
    }

    private var miniMapRegion: MKCoordinateRegion {
        let points = routeSegments.flatMap { $0 }
        guard let firstLat = points.map(\.latitude).min(),
              let lastLat = points.map(\.latitude).max(),
              let firstLng = points.map(\.longitude).min(),
              let lastLng = points.map(\.longitude).max(),
              !points.isEmpty else {
            return MKCoordinateRegion(
                center: trail.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (firstLat + lastLat) / 2,
                                           longitude: (firstLng + lastLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((lastLat - firstLat) * 1.4, 0.02),
                                   longitudeDelta: max((lastLng - firstLng) * 1.4, 0.02)))
    }

    private var miniMap: some View {
        Map(initialPosition: .region(miniMapRegion)) {
            ForEach(routeSegments.indices, id: \.self) { index in
                MapPolyline(coordinates: routeSegments[index])
                    .stroke(Color.orange.opacity(0.9), lineWidth: 3)
            }
            Marker(trail.name, coordinate: trail.coordinate)
                .tint(trail.difficultyColor)
        }
        .id(routeSegments.count)
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
    }
}

struct StatCell: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
