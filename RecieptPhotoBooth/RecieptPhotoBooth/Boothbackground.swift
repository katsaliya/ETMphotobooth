import SwiftUI

/// Shared white full-bleed background used by every screen, plus the
/// reusable pieces that repeat across them (logo/connection button,
/// title text, "tag us", consent notice) — defined once here, referenced
/// individually from each screen's body so each screen controls its own
/// layout/placement.
struct Boothbackground<Content: View>: View {
    var backgroundColor: Color = .white
    @ViewBuilder let content: Content

    init(backgroundColor: Color = .white, @ViewBuilder content: () -> Content) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        ZStack {
            backgroundColor
            content
        }
        .ignoresSafeArea()
    }
}

/// The elephant logo, doubling as the printer connection indicator —
/// full color when connected, grayscale + dimmed when not. Tapping it
/// calls `onTap`, which each screen wires to open PrinterManagementView.
struct EmporiumLogoButton: View {
    let isConnected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 239, height: 73)
                .grayscale(isConnected ? 0 : 1)
                .opacity(isConnected ? 1 : 0.6)
                .animation(.easeInOut, value: isConnected)
        }
    }
}

/// Shared title styling (Cossette Titre, sized/scaled consistently).
/// Text content is passed in since Welcome ("EMPORIUM THAI MARKET") and
/// Review ("thanks for being sexy") use different copy but the same look.
struct EmporiumTitleText: View {
    let text: String
    var size: CGFloat = 79.65556
    var color: Color = .black

    var body: some View {
        Text(text)
            .font(.cossetteTitre(size: size, weight: .bold))
            .multilineTextAlignment(.center)
            .foregroundColor(color)
            .frame(width: 700)
            .tracking(-2)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
}

/// "tag us / @emporiumthaimarket" — identical everywhere it appears, so
/// no parameters needed. Positions itself bottom-right; place inside a
/// ZStack the same way on each screen that uses it.
struct TagUsText: View {
    var color: Color = EmporiumStyle.accentPink

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: -10) {
                    Text("tag us")
                    Text("@emporiumthaimarket")
                }
                .font(.cossetteTitre(size: 39.78751, weight: .bold))
                .tracking(-1)
                .foregroundColor(color)
                .frame(width: 450, alignment: .topTrailing)
                .padding(.trailing, 45)
                .padding(.bottom, 40)
            }
        }
    }
}

/// The cheeky consent notice — identical everywhere it appears.
/// Positions itself bottom-left.
struct ConsentNoticeText: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Text("heads up!— snap here and you're giving Emporium Thai Market the okay to post your gorgeous face on our socials")
                    .font(.epilogue(size: 7, weight: .light))
                    .multilineTextAlignment(.leading)
                    .foregroundColor(EmporiumStyle.accentPink)
                    .frame(width: 800, alignment: .topLeading)
                    .padding(.leading, 45)
                    .padding(.bottom, 40)
                Spacer()
            }
        }
    }
}

#Preview {
    Boothbackground {
        Color.clear
    }
}
