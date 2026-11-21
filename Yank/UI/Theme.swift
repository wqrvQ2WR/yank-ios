import SwiftUI

/// 채도 높은 보라 - 자홍 - 주황 (안드로이드 Yank 와 같은 색)
enum Brand {
    static let violet = Color(red: 0x6D / 255, green: 0x2B / 255, blue: 1)
    static let magenta = Color(red: 1, green: 0x2E / 255, blue: 0x93 / 255)
    static let amber = Color(red: 1, green: 0x8A / 255, blue: 0)
    static let gradient = LinearGradient(colors: [violet, magenta, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let soft = LinearGradient(colors: [violet.opacity(0.12), magenta.opacity(0.10), amber.opacity(0.10)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
}

func L(_ key: String) -> String { String(localized: String.LocalizationValue(key)) }
func LF(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }

struct GradientButtonStyle: ButtonStyle {
    var enabled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(enabled ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.gray.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Header: View {
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 30, weight: .heavy, design: .rounded))
            if let subtitle { Text(subtitle).font(.subheadline).opacity(0.9) }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 18)
        .background(Brand.gradient.ignoresSafeArea(edges: .top))
    }
}

struct Thumb: View {
    var url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init)) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            ZStack { Brand.soft; Image(systemName: "play.rectangle").foregroundStyle(Brand.violet.opacity(0.6)) }
        }
        .frame(width: 112, height: 63)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct Chip: View {
    var title: String
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(selected ? .white : Brand.violet)
                .background(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.violet.opacity(0.1)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
