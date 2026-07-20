import SwiftUI

/// 可交互五星评分选择器
struct StarPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.title2)
                    .foregroundStyle(star <= rating ? .yellow : Color.secondary)
                    .onTapGesture {
                        rating = (rating == star) ? 0 : star
                    }
            }
            if rating > 0 {
                Text("\(rating) 星")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 只读星级展示
struct StarDisplay: View {
    let rating: Int
    var size: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(size)
                    .foregroundStyle(star <= rating ? .yellow : Color.secondary.opacity(0.4))
            }
        }
    }
}
