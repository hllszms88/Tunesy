import SwiftUI

/// Camera effects: browse, preview live, and keep favourites.
struct FiltersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFavoritesOnly = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 6)
            Spacer(minLength: 0)
            if model.filter.kind == .face {
                FaceHint(live: model.live)
                    .padding(.bottom, 10)
            }
            FilterTray(favorites: model.favorites, showFavoritesOnly: $showFavoritesOnly)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 84)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.filter.symbol)
                    .font(.system(size: 14, weight: .bold))
                Text(model.filter.title)
                    .font(Theme.label(15, weight: .bold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .glassCard(cornerRadius: 22)

            Spacer(minLength: 0)

            if model.filter != .original {
                IconButton(systemName: "xmark") {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.filter = .original
                    }
                }
                FavoriteButton(favorites: model.favorites, filter: model.filter)
            }
            IconButton(systemName: "arrow.triangle.2.circlepath.camera") { model.switchCamera() }
        }
    }
}

/// Heart toggle for the current filter.
struct FavoriteButton: View {
    @ObservedObject var favorites: FavoritesStore
    let filter: CameraFilter

    var body: some View {
        let saved = favorites.contains(filter)
        IconButton(systemName: saved ? "heart.fill" : "heart", isOn: saved,
                   tint: Color(red: 1.0, green: 0.36, blue: 0.52)) {
            favorites.toggle(filter)
        }
        .sensoryFeedback(.selection, trigger: saved)
        .accessibilityLabel(saved ? "Remove from favourites" : "Add to favourites")
    }
}

/// Tells the user when a face filter is selected but no face is in view.
struct FaceHint: View {
    @ObservedObject var live: LiveState

    var body: some View {
        if live.frame.face == nil {
            Label("Bring your face into view", systemImage: "face.dashed")
                .font(Theme.label(13))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassCard(cornerRadius: 18)
        }
    }
}

/// The scrolling row of filters with an All / Favourites switch.
struct FilterTray: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var favorites: FavoritesStore
    @Binding var showFavoritesOnly: Bool

    private var filters: [CameraFilter] {
        showFavoritesOnly ? favorites.filters : CameraFilter.allCases
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 2) {
                scopeButton("All", favoritesOnly: false)
                scopeButton("Favourites", favoritesOnly: true)
                Spacer(minLength: 0)
            }

            if filters.isEmpty {
                Text("Tap the heart on a filter to keep it here.")
                    .font(Theme.label(13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .frame(height: 86)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(filters) { filter in
                            FilterChip(filter: filter,
                                       selected: model.filter == filter,
                                       favorite: favorites.contains(filter)) {
                                withAnimation(.snappy(duration: 0.2)) {
                                    model.filter = filter
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(height: 86)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 24)
    }

    private func scopeButton(_ title: String, favoritesOnly: Bool) -> some View {
        let selected = showFavoritesOnly == favoritesOnly
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                showFavoritesOnly = favoritesOnly
            }
        } label: {
            Text(title)
                .font(Theme.label(13, weight: .bold))
                .foregroundStyle(selected ? Theme.ink : Color.white.opacity(0.8))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule().fill(Color.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct FilterChip: View {
    let filter: CameraFilter
    let selected: Bool
    let favorite: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(LinearGradient(colors: filter.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: filter.symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .shadow(color: Color.black.opacity(0.35), radius: 3, y: 1)
                        }
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: selected ? 3 : 0)
                        }
                        .scaleEffect(selected ? 1.0 : 0.9)
                    if favorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.52))
                            .padding(4)
                            .background(Circle().fill(Color.white))
                            .offset(x: 3, y: -1)
                    }
                }
                Text(filter.title)
                    .font(Theme.label(11, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
    }
}
