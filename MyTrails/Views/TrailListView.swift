import SwiftUI

struct TrailListView: View {
    let trails: [Trail]
    var title = "步道"
    var emptyText = "没有符合条件的步道"

    var body: some View {
        List(trails) { trail in
            NavigationLink(value: trail) {
                TrailRow(trail: trail)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Trail.self) { trail in
            TrailDetailView(trail: trail)
        }
        .overlay {
            if trails.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "figure.hiking")
            }
        }
    }
}

struct TrailRow: View {
    let trail: Trail

    var body: some View {
        HStack(spacing: 12) {
            CoverThumb(url: trail.coverURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(trail.name)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(trail.locationLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    DifficultyBadge(trail: trail)
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", trail.rating))
                        Text("(\(trail.formattedReviews))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    Text(trail.formattedDistance)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct CoverThumb: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Color.trailGreen.opacity(0.15)
                    Image(systemName: "figure.hiking")
                        .foregroundStyle(Color.trailGreen)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct DifficultyBadge: View {
    let trail: Trail

    var body: some View {
        Text(trail.difficultyLabel)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(trail.difficultyColor)
            .background(trail.difficultyColor.opacity(0.15), in: Capsule())
    }
}
