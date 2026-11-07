# Booth By Liya — Receipt Photo Booth (iPad kiosk)

SwiftUI iPad/iPhone app (iOS 26.5, bundle `ETM.Liya.RecieptPhotoBooth`, display name "Booth By Liya").
Guests take photos, which are composed into a receipt-style strip, printed on a Star Micronics thermal
printer (StarXpand SDK / `StarIO10` via SPM), saved to Photos, and offered via AirDrop. Branded for
Emporium Thai Market.

## ⚠️ Hard rule: design only

**Never change camera, printing, or upload/save code. Only change the design (layout, colors, fonts, copy, spacing, assets used for on-screen UI).**

Off-limits files — do not edit:

| File | What it does |
|---|---|
| `CameraCaptureManager.swift` | AVCaptureSession, front camera, orientation, countdown, `runBoothSequence`, photo capture |
| `FilteredCameraPreview.swift` | Live Metal-rendered filtered preview (`UIViewRepresentable`), attach/detach of video output |
| `BoothFilter.swift` | Black-and-white conversion for the print only. No effects (owner removed contrast/bloom/grain on Nov 5, 2026 — don't add filters back without asking) |
| `PrintManager.swift` | Star printer discovery, auto-connect, `printStrip` (dithering, raster) |
| `StripComposer.swift` | Composes photos onto the chosen `BoothFrame`'s template (same windows as on screen), 576pt print width. Changed Nov 6, 2026 at the owner's request |
| `Sharesheet.swift` | `UIActivityViewController` wrapper (AirDrop) |
| `FrameConfig.swift` | Persisted config: shot count, interval, template mode, saved printer ID |
| `Info.plist`, `Assets.xcassets/Frame*` | Permissions, printer protocols; the frame templates are what prints, so swap them only on the owner's request |

Off-limits logic inside view files (the views mix UI with behavior — edit the look around it, not the calls):

- `WelcomeView` `.onAppear { camera.start(); printer.autoConnect() }`
- `CaptureView` `.onAppear { camera.runBoothSequence(...) }` and its `shotCount`/`interval` arguments
- `ReviewView` `.onAppear` (compose mono → autoprint) and `autoprint(_:)`
- `PrinterManagementView` calls to `startDiscovery` / `stopDiscovery` / `selectPrinter` / `autoConnect(force:)` / `disconnect`
- `RootView` screen-state machine, the `@StateObject` camera/printer ownership, and the 15s idle-reset timer
- `RecieptPhotoBoothApp` idle-timer disabling / hidden status bar (kiosk behavior)

Design constraint that touches camera/print: the on-screen photo windows come from the same `BoothFrame`
slots that `StripComposer` prints into, so what guests see matches what prints. Keep both on `BoothFrame`.
The capture flash preview uses `alignment: .top` to match the print crop — keep that too.

Network upload exists (Nov 6, 2026): `Delivery.swift` `UploadQueue` sends each session's strip.jpg + live.mp4
to the photo page Worker in `/photo-page` (Cloudflare Workers + R2). Don't change camera or printer logic
when working on it.

## Project layout

- **Active app target:** `RecieptPhotoBooth/RecieptPhotoBooth/` (Xcode "file system synchronized group",
  so any `.swift` file dropped in this folder is compiled automatically). Open
  `RecieptPhotoBooth/RecieptPhotoBooth.xcodeproj`.
- **Legacy, NOT compiled:** top-level `ReceiptPhotoBooth/` (correct spelling) — an older version with
  `PhotoBoothApp`, `FrameSettingsView`, `PrinterSetupView`. Don't edit it for redesign work; it doesn't ship.
- Fonts: `RecieptPhotoBooth/RecieptPhotoBooth/*.ttf`, registered in `Info.plist` `UIAppFonts`.

## Design system (`EmporiumStyle.swift` + `Boothbackground.swift`)

Change these first — they're shared across every screen.

**Colors** (`EmporiumStyle`):
- `accentPink` — `rgb(1, 0.44, 0.72)`: strokes, countdown, tag-us, consent text, Review background
- `buttonFill` — `rgb(1, 0.957, 0.976)`: pale pink ellipse button fill
- `boxFill` — `rgb(0.85, 0.85, 0.85)`: gray placeholder behind camera/strip

**Fonts** (`Font` extension):
- `.cossetteTitre(size:weight:)` → `CossetteTitre-Bold` (titles, countdown, Review buttons, tag us)
- `.epilogue(size:weight:)` → `Epilogue-VariableFont_wght` (body, "start", status text). Note: `weight` is ignored — the custom font name is fixed.
- `.pinyonScript(size:)` → `PinyonScript-Regular` (Review "Thank you!" / "See you soon <3")
- `.iosevkaCharonMono(size:)` — defined but unused and not bundled

**Shared components** (`Boothbackground.swift`):
- `Boothbackground(backgroundColor:) { ... }` — full-bleed `ZStack` (default white), ignores safe area. Every guest screen is wrapped in it.
- `EmporiumLogoButton(isConnected:onTap:)` — `Logo` asset 239×73. It also shows printer status: full color when connected, grayscale at 60% opacity when not. Tapping it opens `PrinterManagementView` (hidden staff entry point — keep it tappable).
- `EmporiumTitleText(text:size:color:)` — Cossette 79.66pt, tracking −2, 700pt wide, one line, scales down to 50%.
- `TagUsText(color:)` — "tag us / @emporiumthaimarket", bottom-right, Cossette 39.79pt, pink.
- `ConsentNoticeText()` — tiny (7pt Epilogue light) photo-consent line, bottom-left, pink.

Layout is hand-tuned in absolute points for a landscape iPad (e.g. 855pt preview, 252×57 button,
45pt side insets, 40pt bottom insets). Nothing is adaptive — check any change on the iPad simulator in landscape.

## Navigation (`Rootview.swift`)

`RootView` holds `@State currentScreen: BoothScreen` and switches between screens with closures —
no `NavigationStack`, so there are no back buttons or swipe gestures (kiosk).

```
welcome --(tap "start")--> capture --(all shots done)--> review(photos, colorPhotos) --(tap "take more!")--> welcome
```

Any screen except Capture returns to Welcome after 15s with no touches. `camera` and `printer` are
`@StateObject`s owned here so the camera feed stays running from Welcome into Capture.

## Screens

### 1. Welcome — `Welcomeview.swift`
`Boothbackground` (white) → top-aligned `VStack(spacing: 0)`:
1. 20pt spacer
2. `EmporiumLogoButton` (opens printer sheet)
3. `EmporiumTitleText("EMPORIUM THAI MARKET")`, +6pt
4. `FilteredCameraPreview` — 855pt wide × slot-aspect height, gray fill, 6pt corner radius, 1pt pink stroke, +20pt
5. "start" button — 252×57 `Ellipse` (buttonFill + pink stroke) with "start" in Epilogue 24, tracking −2, black, +18pt. Calls `onStart`.
6. `Spacer()`

Overlaid in the same ZStack: `ConsentNoticeText()` (bottom-left), `TagUsText()` (bottom-right).
`.sheet` → `PrinterManagementView`.

### 2. Capture — `CaptureView.swift`
Same skeleton as Welcome so the switch between the two screens looks seamless:
1. 20pt spacer
2. `Image("Logo")` 239×73 (plain image, not the button — no printer status, can't be tapped)
3. `EmporiumTitleText("EMPORIUM THAI MARKET")`, +6pt
4. Camera `ZStack`, same size and styling as Welcome's preview, with these layers:
   - `FilteredCameraPreview`
   - countdown number (`camera.countdownText`) — Cossette 90, pink, black shadow r10
   - last captured photo flash (`camera.lastCapturedImage`), top-aligned fill, `.transition(.opacity)`
   - "x/y" shot counter pill, top-right — Epilogue 16 white on pink capsule at 85% opacity
5. Same 252×57 ellipse, but it isn't a button. It shows a per-shot emoji prompt (`shotEmoji`: 😜😜😜 / ✌️✌️✌️ / 💋💋💋 for shots 1–3).
6. `Spacer()`

Overlaid: `ConsentNoticeText()`, `TagUsText()`. Shooting starts automatically on appear.

### 3. Review / Thank-you — `Reviewview.swift`
`Boothbackground(backgroundColor: accentPink)` → `VStack(spacing: 0)`:
1. 40pt spacer, `EmporiumLogoButton`, `Spacer()`
2. Center `HStack(spacing: 40)`, 50pt horizontal padding:
   - "Thank you!" — Pinyon Script 64, white, 260pt wide, nudged down 70pt
   - two `stripPreview`s in an `HStack(spacing: 20)`: "color" (`colorStrip`) and "b&w" (`strip`). Each is an Epilogue 12 caption over the image, 380pt tall on white, with a 200×380 gray placeholder while composing.
   - "See you \nsoon <3" — Pinyon Script 64, white, centered, 260pt wide, nudged up 70pt
3. Status lines, each shown only when it applies: "printing…" (`printer.isPrinting`), `printMessage`, `saveMessage` — Epilogue 13 / 11, white
4. `Spacer()`
5. Bottom `HStack(spacing: 55)` of `textButton`s (Cossette 39.79, white, 40% opacity when disabled):
   "airdrop" (opens share sheet) · "reprint" · "take more!" (`onDone`), 75pt bottom padding

No `TagUsText` / `ConsentNoticeText` here (matches the Figma mockup). Sheets: `ShareSheet`, `PrinterManagementView`.

### 4. Printer management (staff sheet) — `Printermanagementview.swift`
Opened by tapping the logo on Welcome or Review. A standard `NavigationStack` + `List` titled "Printer",
with a "Done" toolbar button:
- Status section: green/red dot + "Connected"/"Not connected", spinner while connecting, identifier, last error
- "Available Printers": discovered devices (identifier + interface type), checkmark on the connected one
- Actions: "Rescan", "Disconnect" (destructive, only when connected)

Uses Epilogue at various sizes; otherwise stock iOS styling. Only restyle it — keep every action call as is.

### Not a screen: the printed strip
The printed and saved strip is made by `StripComposer` from the frame the guest picked (`BoothFrame` template image + windows).

## New user flow (in progress)

The redesign spec is [docs/user-flow.md](docs/user-flow.md) (screens 01 Pick a frame, 03 Countdown,
04 Printing, 05 Text me + Sent; teal theme). Decisions so far (Nov 5, 2026):
- **UI only.** Live-clip recording, upload, and RingCentral texting get placeholder hooks with no
  behavior. Printing keeps today's `StripComposer` templates (Holiday prints like Classic for now).
- New theme tokens, frame list, and screen copy live in `BoothTheme.swift` (data, not hard-coded in views).
- Picking a frame writes `FrameConfigStore.shared.config.templateMode` (the existing public config value)
  so Solo shoots 1 photo — `FrameConfig.swift` itself is unchanged.
- Only one `FilteredCameraPreview` may be on screen at a time (each one adds a video output to the
  shared session). On 01 the live feed fills the first slot; other slots use the sage placeholder.
- Frames on screen use the owner's real templates (Nov 6, 2026): `Assets.xcassets/FrameClassic|FrameSolo|FrameHoliday`
  (from Photobooth_Classic3 / Classic1 / Holiday26.png, ~2300px wide, transparent photo windows; Holiday replaced Nov 6 with the black doodle version, 2277×4596).
  Window rects live in `BoothFrame.all` (template pixels). The SAME frame prints: RootView passes the
  picked frame Welcome → Capture → Review → `StripComposer.composeStrip(photos:frame:)`; shot count = `frame.photoCount`.
  The old `PrintTemplate*` assets are no longer used.
- Doc colors are approximate until the Figma file link is provided; then match exact values via the Figma MCP.
- 03 Countdown lives in `CaptureView.swift` and only reads `CameraCaptureManager`'s published state
  (`currentShotIndex`, `countdownText`, `capturedColorImages`, `isRunningSequence`).
  No Cancel on the countdown (owner's call, Nov 6, 2026): once started, a session always runs to the end.
- Live capture (Nov 6, 2026, owner's request — camera code touched on purpose):
  - `LiveFrameBuffer` keeps a rolling ~2.5 s of downscaled, mirrored frames, fed from
    `FilteredCameraPreview.captureOutput` (so a preview must be on screen; the countdown slot always has one).
  - `CameraCaptureManager.runBoothSequence` marks the shutter time and stores each shot's run-up in `capturedRunUps`.
  - `RootView.exportLive` runs `LiveExporter` in the background after every session →
    `Documents/Sessions/<date-time>/strip.jpg` (color, same `StripComposer` layout as the print) and
    `live.mp4` (1080×1920, 30 fps; all slots play run-up → freeze on photo → reset, ≥6 s).
  - Settings: `FrameConfig.liveRunUpSeconds` (1–2 s) / `liveFreezeSeconds` (0.5–4 s), steppers in the staff printer sheet.
  - Files app access is on (`UIFileSharingEnabled`). Nothing is uploaded yet.
  - The project defaults every type to MainActor; the export path (`LiveExporter`, `LiveFrameBuffer`, `StripComposer`,
    `BoothFrame`, `TemplateMode`) is marked `nonisolated` so it runs off the main thread. Keep it that way.
  - The B&W print path (ReviewView → StripComposer mono → PrintManager) is unchanged.
- 04 Printing + text me (`Reviewview.swift`, Nov 6, 2026) replaced the old pink review screen. The B&W
  print + Photos save code paths inside it are unchanged. Left: color stills → live MP4 (`LiveStripVideo`,
  aligned to the same strip rect, no LIVE badges) + print status. Right: keypad / consent / Sent.
  `LiveExportJob` (LiveSession.swift) owns the export per session. Idle: 30 s on this screen; Sent returns after 20 s with no touches.
  The old AirDrop and Reprint buttons are gone (not in the spec).
- CURRENT PHASE — QR instead of texting (Nov 6, 2026). `BoothFeatures.textingEnabled = false` (TEXTING_ENABLED)
  in `Delivery.swift`; the keypad / consent / Sent UI stays in `Reviewview.swift` behind it — don't delete it.
  - Screen 04 right side = `QRPanel`: QR for `<BASE_URL>/p/<sessionID>` shown immediately at the last shot,
    "Uploading…" → "Ready ✓", Take another / Done. Idle reset 45 s on this screen (30 s if texting is on).
  - `SessionID.make()`: 7 base36 chars of unix seconds + 16 random URL-safe chars. Must match `ID_PATTERN`
    in `photo-page/src/index.ts`.
  - `UploadQueue` (Delivery.swift): persisted to `Documents/upload-queue.json`, retries with backoff and on
    network return, resumes at launch (`RootView.onAppear`). Deletes local `Documents/Sessions/<id>/` once both
    files are up (not while that session is on screen), and anything older than 3 days.
  - Config: `RecieptPhotoBooth/RecieptPhotoBooth/BoothDelivery.plist` (BASE_URL, BOOTH_KEY) is git-ignored;
    template `RecieptPhotoBooth/BoothDelivery.example.plist`. Missing config → QR panel says "not set up".
  - Photos library (Nov 6, 2026, owner's request): each session saves ONLY the color strip JPG and the live MP4
    to the iPad's Photos (`PhotoLibrarySaver` in LiveSession.swift, called from `LiveExportJob` before each file
    goes to the upload queue). The B&W print version is no longer saved. `ReviewView.saveStripLocally` is gone.
  - Backend: `/photo-page` (see its README for setup, local dev and `npm test`). Deployed Nov 6, 2026 on the
    restaurant's Cloudflare account (emporiumthaimarket@gmail.com): https://etm-photobooth.etm-photobooth-photo-page.workers.dev,
    R2 bucket `etm-photobooth` with lifecycle rule `delete-after-3-days` on `sessions/` (owner chose 3 days, Nov 6). Node LTS is in `~/.local/node`. Texting (`DeliveryService`) is
    still a stub; phone numbers are never stored.
- The "● Recording a live clip" line is hidden (`BoothCopy.Countdown.showLiveClipLine = false`)
  until live-clip capture exists. No LIVE badge on the countdown slot (owner's call).
- Countdown number: plain system font, white. The camera's "📸" at the shutter is hidden in the UI.
- The simulator has no camera: `capturePhoto` throws and crashes after the first 3-2-1 countdown.
  That's existing camera code, not a UI bug. Test full sessions on the iPad.

## Redesign workflow

- Work on the `figma-redesign` branch. `main` has the "before Figma redesign" snapshot.
- Change shared tokens/components in `EmporiumStyle.swift` / `Boothbackground.swift` first, then each screen's `body`.
- When implementing from Figma, map Figma colors/text styles to `EmporiumStyle` / the `Font` helpers instead of hard-coding values in screens.
- New fonts: add the `.ttf` to `RecieptPhotoBooth/RecieptPhotoBooth/`, list it in `Info.plist` `UIAppFonts` (the only allowed Info.plist edit), and add a `Font` helper.
- Verify on an iPad simulator in landscape. `#Preview`s exist for Welcome and Capture (no camera feed in previews).
