import SwiftUI

enum RoadarTheme {
    static let background = Color(red: 0.025, green: 0.032, blue: 0.037)
    static let surface = Color(red: 0.055, green: 0.067, blue: 0.075)
    static let elevated = Color(red: 0.10, green: 0.12, blue: 0.13)
    static let accent = Color(red: 0.64, green: 0.98, blue: 0.79)
    static let secondary = Color(red: 0.68, green: 0.73, blue: 0.74)
    static let border = Color.white.opacity(0.12)
}

struct RoadarSurface: ViewModifier {
    var radius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(RoadarTheme.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(RoadarTheme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 20, y: 8)
    }
}

struct RoadarPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(RoadarTheme.background)
            .background(RoadarTheme.accent, in: RoundedRectangle(cornerRadius: 16))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

struct RoadarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(RoadarTheme.accent)
            .frame(width: 48, height: 48)
            .background(configuration.isPressed ? RoadarTheme.elevated : RoadarTheme.surface, in: Circle())
            .overlay(Circle().strokeBorder(RoadarTheme.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension View {
    func roadarSurface(radius: CGFloat = 28) -> some View {
        modifier(RoadarSurface(radius: radius))
    }

    func roadarSheet() -> some View {
        scrollContentBackground(.hidden)
            .background(RoadarTheme.background)
            .tint(RoadarTheme.accent)
            .preferredColorScheme(.dark)
    }
}
