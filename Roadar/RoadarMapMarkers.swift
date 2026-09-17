import SwiftUI

/// Screen-space halo is decorative, not a GPS accuracy radius.
struct RoadarLocationMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(RoadarTheme.accent.opacity(0.12)).frame(width: 52, height: 52)
            Circle().strokeBorder(RoadarTheme.accent.opacity(0.35), lineWidth: 1)
                .frame(width: 40, height: 40)
            Circle().fill(RoadarTheme.accent).frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(RoadarTheme.background, lineWidth: 3))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your location")
        .accessibilityIdentifier("userLocationMarker")
    }
}

struct RoadarDestinationMarker: View {
    let name: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(RoadarTheme.accent)
                Text(name).font(.caption.weight(.bold)).lineLimit(1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoadarTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RoadarTheme.accent, lineWidth: 1.5))
            Rectangle().fill(RoadarTheme.accent).frame(width: 2, height: 12)
            Circle().fill(RoadarTheme.accent).frame(width: 6, height: 6)
        }
        .frame(maxWidth: 200)
        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
        .accessibilityLabel("Destination: \(name)")
    }
}
