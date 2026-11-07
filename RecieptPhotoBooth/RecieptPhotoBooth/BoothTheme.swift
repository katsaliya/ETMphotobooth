import SwiftUI

/// Teal redesign tokens (docs/user-flow.md, "Visual direction").
/// Values are close matches from the Figma frame 1 screenshot — swap in the
/// exact Figma values here once the file link is available.
enum BoothTheme {
    static let background = Color(hex: 0x428EA8)
    static let primaryButton = Color(hex: 0x2A526B)
    static let slotPlaceholder = Color(hex: 0xD4DBD5)
    static let tileFill = Color.white.opacity(0.2)
    static let divider = Color.black.opacity(0.55)
    static let arrowChevron = Color(hex: 0xD7263D)
    /// Current segment of the countdown progress bar (Figma frames 6–8
    /// highlight only the shot in progress, in soft pink).
    static let progressActive = Color(hex: 0xF7CFC8)

    /// Large black serif headline.
    static func headline(_ size: CGFloat = 64) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    /// Body / labels: white sans. Kept semibold and ≥15pt so it survives
    /// the pink neon wash in the room.
    static func body(_ size: CGFloat = 18, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// Small-caps style section label ("CHOOSE A FRAME", "PHOTOBOOTH").
    static func label(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .bold)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Frames (data, not hard-coded in views)

/// One selectable strip frame on the home screen. Seasonal frames are
/// just more entries in `BoothFrame.all`.
///
/// Each frame is a designed template image (Assets.xcassets/Frame*) with
/// transparent photo windows. `slots` are those windows in the template's
/// own pixels, measured off its alpha channel — re-measure if a template
/// is swapped.
nonisolated struct BoothFrame: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Which existing print layout this frame uses (decides 1 vs 3 shots).
    let templateMode: TemplateMode
    /// Asset name of the template image.
    let templateImage: String
    /// Template image size in pixels.
    let templateSize: CGSize
    /// Transparent photo windows, top to bottom, in template pixels.
    let slots: [CGRect]

    var photoCount: Int { slots.count }

    /// "Classic strip • 3 photos"
    var caption: String {
        "\(name) • \(photoCount) photo\(photoCount == 1 ? "" : "s")"
    }

    static let all: [BoothFrame] = [
        BoothFrame(
            id: "classic", name: "Classic strip",
            templateMode: .threePhotoStrip,
            templateImage: "FrameClassic",
            templateSize: CGSize(width: 2304, height: 4332),
            slots: [
                CGRect(x: 168, y: 603, width: 1968, height: 1035),
                CGRect(x: 168, y: 1644, width: 1968, height: 1035),
                CGRect(x: 168, y: 2685, width: 1968, height: 1035),
            ]
        ),
        BoothFrame(
            id: "solo", name: "Solo",
            templateMode: .singlePhoto,
            templateImage: "FrameSolo",
            templateSize: CGSize(width: 2304, height: 3687),
            slots: [CGRect(x: 51, y: 624, width: 2202, height: 2661)]
        ),
        BoothFrame(
            id: "holiday", name: "Holiday strip",
            templateMode: .threePhotoStrip,
            templateImage: "FrameHoliday",
            templateSize: CGSize(width: 2277, height: 4596),
            slots: [
                CGRect(x: 138, y: 798, width: 2001, height: 1194),
                CGRect(x: 138, y: 2030, width: 2001, height: 1194),
                CGRect(x: 138, y: 3262, width: 2001, height: 1194),
            ]
        ),
    ]
}

// MARK: - Screen copy (data, not hard-coded in views)

enum BoothCopy {
    enum Home {
        static let brandLabel = "PHOTOBOOTH"
        static let headlineLead = "Strike a "
        static let headlineAccent = "pose."
        static let sub = "Only sexy people eat @emporiumthaimarket"
        static let chooseLabel = "CHOOSE A FRAME"
        static let chooseHint = "tap a frame or swipe the preview"
        static let swipeHint = "← swipe to change frames →"
        static let startButton = "I'm ready"
        /// Shown on the start button while a cancelled session is still
        /// winding down (the camera sequence can't be stopped mid-way).
        static let startButtonBusy = "One sec…"
        static let footer = "tag us @emporiumthaimarket"
    }

    /// 04 · Printing + text me my photos (one shared screen).
    enum Printing {
        static let printing = "Printing your strip…"
        static let printingHint = "Grab the black & white print from the printer."
        static let printed = "Printed ✓"
        static let noPrinter = "Printer not connected. Please ask a staff member."
        static let printFailed = "The print didn't go through. Please ask a staff member."
        static let takeAnother = "Take another"
    }

    /// 04 right side, current phase: QR code to the photo page.
    enum QR {
        static let lookingGood = "Looking good."
        static let headlineLead = "Scan for your photos in "
        static let headlineAccent = "color & live."
        static let sub = "Point your phone camera at the code. Save the photo + video, then tag us @emporiumthaimarket."
        static let uploading = "Uploading…"
        static let ready = "Ready ✓"
        static let notSetUp = "Photo link isn't set up yet.\nPlease ask a staff member."
        static let takeAnother = "Take another"
        static let done = "Done"
    }

    enum TextMe {
        static let lookingGood = "Looking good."
        static let headlineLead = "Text me my photos in "
        static let headlineAccent = "color & live."
        static let sub = "Join our texts and we'll send the color photo + live version."
        static let phonePlaceholder = "(___) ___-____"
        static let clear = "Clear"
        static let delete = "Delete"
        static let button = "Join & text my photos"
        static let noThanks = "No thanks"

        /// Still to decide (docs/user-flow.md): max texts per month, and the
        /// Terms / Privacy page links.
        static let maxMessagesPerMonth = "4"

        /// Exact consent wording. Bump `consentVersion` whenever any of this
        /// text changes — the version is stored with every signup.
        static let consentVersion = "2026-11-06"
        static let consentLabel = "Yes! Text me my photos, plus deals and event invites from Emporium Thai Market."
        static var consentFinePrint: String {
            "By checking this box, you agree to get recurring automated marketing texts from Emporium Thai Market at the number above. Up to \(maxMessagesPerMonth) msgs/month. Consent is not a condition of purchase. Msg & data rates may apply. Reply STOP to cancel, HELP for help. Terms · Privacy"
        }

        static let sentHeadlineLead = "Sent. Check your "
        static let sentHeadlineAccent = "texts."
        static func sentOnTheWay(_ phone: String) -> String {
            "Your color photos and live video are on the way to \(phone)."
        }
        static let sentOnList = "You're on the list. First invite's coming soon."
        static let done = "Done"
    }

    enum Countdown {
        struct Shot {
            let lead: String
            /// Last word(s) of the headline, in white italic.
            let accent: String
            let sub: String
        }

        static let cameraHint = "CAMERA IS UP HERE ⤴"
        static func shotLabel(_ n: Int, of total: Int) -> String { "SHOT \(n) OF \(total)" }
        static let nextLabel = "Next"

        /// "● Recording a live clip with every shot". Hidden until live-clip
        /// capture actually exists — don't tell guests we're recording when we aren't.
        static let showLiveClipLine = false
        static let liveClipLine = "Recording a live clip with every shot"

        /// One entry per shot; change seasonally. Solo uses the first.
        static let shots: [Shot] = [
            // "\n" = the line breaks in Figma frames 5–8.
            Shot(lead: "Look at the\n", accent: "camera.", sub: "Squeeze in. Bring the Pad See Ew."),
            Shot(lead: "Now be\n", accent: "weird.", sub: "Silly faces only please."),
            Shot(lead: "Last one.\nMake it ", accent: "cute.", sub: "💋💋💋💋💋💋"),
        ]
    }
}
