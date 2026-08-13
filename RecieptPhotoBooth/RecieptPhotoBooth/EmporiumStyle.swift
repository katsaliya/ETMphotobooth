import SwiftUI

/// Colors and fonts pulled directly from Figma Dev Mode, shared across
/// every screen so Welcome/Capture/Review all stay visually consistent.
/// Update values here once, rather than in each screen separately.
enum EmporiumStyle {
    static let accentPink = Color(red: 1, green: 0.44, blue: 0.72)
    static let buttonFill = Color(red: 1, green: 0.957, blue: 0.976)
    static let boxFill = Color(red: 0.85, green: 0.85, blue: 0.85)
}

extension Font {
    static func cossetteTitre(size: CGFloat, weight: Font.Weight) -> Font {
        // Confirm the exact PostScript name via UIFont.familyNames if
        // this ever stops rendering — CossetteTitre-Bold.ttf must be
        // added to the project and registered in Info.plist.
        .custom("CossetteTitre-Bold", size: size)
    }

    static func epilogue(size: CGFloat, weight: Font.Weight) -> Font {
        .custom("Epilogue-VariableFont_wght", size: size)
    }

    /// ReviewView's "Thank you!" / "See you soon <3" script text. Requires
    /// PinyonScript-Regular.ttf added to the project and registered in
    /// Info.plist's UIAppFonts — same pattern as the other two fonts here.
    static func pinyonScript(size: CGFloat) -> Font {
        .custom("PinyonScript-Regular", size: size)
    }

    static func iosevkaCharonMono(size: CGFloat) -> Font {
        .custom("Iosevka Charon Mono", size: size)
    }
}
