# ETM Photobooth: new user flow (handoff for Claude Code)

Emporium Thai Market (Sawtelle) · iPad photobooth app · updated Nov 5, 2026 with the Figma look

## How to use this doc

- This doc covers **behavior, flow, copy and rules**. The **look** (layout details, colors, fonts, spacing, components) comes from Figma links pasted one screen at a time.
- If Figma and this doc disagree on **visuals**, Figma wins. If they disagree on **behavior, logic or legal copy**, this doc wins. If something is unclear, ask before guessing.
- Do **not** change the existing camera, printing or upload logic unless a task says so. Most tasks are UI changes.
- Work one screen at a time. Build after each change and fix errors before moving on.

## Visual direction (from Figma, Nov 5)

The Figma file has 8 frames. **Frame 1 (home screen, Classic strip) is the finished look.** Frames 2–8 are still gray wireframes. They show layout and copy only. **Style every screen like frame 1.** Pull exact fonts, sizes and colors from Figma through the MCP. The values below are close matches taken from a screenshot.

| Token | Value (approx.) | Used for |
| --- | --- | --- |
| Background | teal `#428EA8` | Full-screen background on every screen |
| Primary button | dark teal `#2A526B`, white bold text, full pill | "I'm ready", "Join & text my photos", other main actions |
| Frame tiles | white at ~20% opacity, rounded; selected = 1.5pt white border | "Choose a frame" tiles |
| Arrow buttons | white ovals, red chevrons | Prev/next frame on the preview |
| Headline | black serif, large; accent word in **white italic** serif (e.g. "Strike a *pose.*") | Main headline on each screen |
| Body / labels | white sans; small caps for section labels ("CHOOSE A FRAME", "PHOTOBOOTH") | Everything else |
| Photo slots in previews | light sage gray `#D4DBD5` | Placeholder for the live camera in the strip |
| Divider | thin dark vertical line between the left and right halves | Home screen |

- Top-right brand mark: the **colorful pop-art elephant herd logo + "PHOTOBOOTH"**.
- **Readability:** the pink neon room washes out thin white text. Small white text on `#428EA8` is below normal contrast. Keep the italic sub and small labels at medium/semibold weight, at least 15pt. Don't make them thinner than in Figma.

**Strip designs (also what prints):**
- **Classic strip (3 photos):** "EMPORIUM THAI MARKET" in a heavy black serif at the top, three photo slots, and the script line *"Do small things with great love."* at the bottom.
- **Solo (1 photo):** the same header, one photo, and the small elephant logo at the bottom.
- **Holiday strip (3 photos):** seasonal version, details in Figma.
- These must look right in black and white for the thermal print.

## Context

- iPad kiosk, **landscape only**, inside the restaurant. Guests walk up with no instructions.
- Prints **black-and-white strips on a thermal receipt printer**. The printed strip is always free.
- The room has **pink neon lighting**, so keep text bold and high-contrast. Touch targets are at least 44pt.
- Strip frames are swappable (seasonal frames, filters). Keep frames and screen copy in config/data, not hard-coded in views.
- Instagram handle: **@emporiumthaimarket**. Online ordering: **emporium-thai-market.square.site**.

## Flow at a glance

```
01 Pick a frame (home)
   └─ "I'm ready" ─► 03 Countdown (3 shots, or 1 for single-photo frames)
                       └─ ► 04 Printing + text me (one screen)
                              ├─ "Join & text my photos" ─► Sent ─► 01 (Done / 20s idle)
                              ├─ "No thanks" / "Take another" ─► 01
                              └─ ~30s idle ─► 01
(No cancel during the countdown: once started, a session runs to the end.)
```

Every return to 01 clears all session data on screen (photos, phone number, checkbox).

## 01 · Pick a frame (home screen)

**Layout:** left = live camera with the strip frame drawn over it as a preview. Right = copy, frame tiles, start button.

**Frames**
- Two kinds: **3-photo strip** and **1-photo**. Seasonal frames (for example "Holiday" with a header) are extra entries in the same list.
- The live camera shows inside every photo slot of the preview, so guests see how they'll fit.

**Changing frames:** three ways that always stay in sync:
1. Swipe left/right on the left preview (about 40pt horizontal threshold)
2. Arrow buttons on the left and right edges of the preview
3. Tapping a frame tile on the right (selected tile is highlighted)

Plus pagination dots and the frame name under the preview (e.g. "Classic strip · 3 photos").

**Starting:** ONLY the start button on the right starts a session. Tapping the preview must NOT start the camera. Reasons: people tap while trying to swipe, and a hand on the preview covers the guest's view of themselves.

**Copy (matches Figma frame 1)**
- Top right: elephant herd logo + PHOTOBOOTH
- Headline: **Strike a *pose.*** ("pose." in white italic)
- Sub (white italic): *Only sexy people eat @emporiumthaimarket*
- Section label: CHOOSE A FRAME · hint: tap a frame or swipe the preview
- Under the preview: frame name and count ("Classic strip • 3 photos", "Solo • 1 photo", "Holiday strip • 3 photos"), dots, and "← swipe to change frames →"
- Button: **I'm ready** (one line, no subline)
- Footer: tag us @emporiumthaimarket

## 03 · Countdown (one screen state per shot)

**Layout flips here (per Figma):** text on the LEFT, strip preview on the RIGHT.

**Strip side:** the strip preview fills in shot by shot:
- Current slot: highlighted outline and the countdown number (3, 2, 1) inside it
- Finished slots: show the captured photo (or a done state)
- Upcoming slots: dimmed, labeled "Next"

**Text side:**
- "CAMERA IS UP HERE ⤴" in the top corner, pointing at where the lens actually is on the booth
- "SHOT N OF 3" plus a progress bar (3 segments, or 1 segment for Solo)
- A new headline and sub for each shot (matches Figma):

| Shot | Headline | Sub |
| --- | --- | --- |
| 1 | Look at the camera. | Squeeze in. Bring the Pad See Ew. |
| 2 | Now be weird. | Silly faces only please. |
| 3 | Last one. Make it cute. | 💋💋💋💋💋💋 |

- Single-photo frames: one shot, shot 1 copy, "SHOT 1 OF 1" and a single-segment progress bar (Figma has this frame).
- Big 3-2-1 number inside the current slot, plain font. No LIVE badge and no Cancel (owner's call, Nov 6).
- Keep these lines in a config array so they can change seasonally.
- Line under the progress bar: ● Recording a live clip with every shot

**Live capture (new)**
- Like an iPhone Live Photo: record about 1.5s before and after each shutter.
  - Built (Nov 6): the run-up *before* each shutter (setting, 1–2 s), then a freeze on the photo (setting). No after-shutter footage yet.
- Stills are used for the print (B&W) and the color digital copy.
- Stitch the clips into one short looping MP4 in color: the "live version".

## 04 · Printing + text me my photos (one shared screen)

Printing and texting happen on the same screen. As soon as the last shot is taken, this screen opens and the B&W strip starts printing.
Figma shows the right-hand panel (headline, phone field, keypad, checkbox, button, "no thanks"). The left side and the Sent state aren't in Figma yet. Build them from this section in the frame 1 style.

**Left: live video preview of the strip**
- The strip (same frame design as the print, in color) plays the live video: all slots run up, freeze on the shot and reset together, looping.
- No LIVE badge on the slots (owner's call, Nov 6).
- If the video takes a few seconds to render, show the color stills first and switch to the video when it's ready. Never show a blank or spinning strip.
- Under the strip, a small printing status: "Printing your strip… Grab the black & white print from the printer." with a progress bar. When printing finishes, it changes to "Printed ✓".
- Small "Take another" link (bottom corner) ▸ 01.
- Start uploading the color strip and live video here, while the strip prints (see Delivery).

**Right: text me my photos**
- Top: elephant herd logo + PHOTOBOOTH (small label "Looking good." is optional)
- Headline (matches Figma): **Text me my photos in color & live.**
- Sub (states the deal BEFORE they type): **Join our texts and we'll send the color photo + live version.**
- Phone field with an on-screen keypad: US 10 digits, shown as (___) ___-____. Figma shows 3 rows of keys; add the 4th row: **Clear · 0 · Delete**
- Consent checkbox: **unchecked by default**. Use this exact text:

  **Label:** Yes! Text me my photos, plus deals and event invites from Emporium Thai Market.

  **Fine print (right under the label, never hidden in a link):** By checking this box, you agree to get recurring automated marketing texts from Emporium Thai Market at the number above. Up to [4] msgs/month. Consent is not a condition of purchase. Msg & data rates may apply. Reply STOP to cancel, HELP for help. [Terms] · [Privacy]

- Button: **Join & text my photos** (primary dark-teal pill), disabled until the number has 10 digits AND the box is checked
- Link: **No thanks** ▸ 01 (the printed strip is still theirs)

**Sent state** (right side swaps; left keeps playing the video)
- Headline: Sent. Check your **texts.**
- "Your color photos and live video are on the way to (xxx) xxx-xxxx."
- "You're on the list. First invite's coming soon."
- **Done** ▸ 01 · auto-return after 20s with no touches (any tap restarts the wait)

**Auto-return:** back to 01 after about 30s with no touches. Any tap (including keypad presses) resets the timer, so nobody gets kicked out mid-typing. Clear the number and checkbox on return.

(Screen 05 was merged into this screen on Nov 6, 2026.)

## CURRENT PHASE: QR code instead of texting (Nov 6, 2026)

Texting is on hold (`TEXTING_ENABLED = false`; the texting UI stays in the app, switched off).
Screen 04's right side shows a QR code instead:
- Headline: Scan for your photos in **color & live.** Sub: Point your phone camera at the code. Save the photo + video, then tag us @emporiumthaimarket.
- Big QR (≥ 280pt) on a white rounded card → `<BASE_URL>/p/<id>`, shown the moment the last shot is taken (before any upload).
- Status under it: "Uploading…" → "Ready ✓". Buttons: Take another · Done ▸ 01. Auto-return after 45s with no touches.
- Uploads run in the background from a queue saved on the iPad: retries through Wi-Fi drops and restarts, deletes local copies once uploaded, keeps nothing longer than 3 days.
- Photo page (Cloudflare Worker + R2, `/photo-page`): looping live video + color strip, Save video / Save photo (share sheet → Save Video / Save Image on iPhone; download link fallback), tag us, Order online, "Photos are deleted after 3 days." Pending: "Your photos are on the way…" (checks every 3s). Unknown/expired: "This link expired". noindex, no public list, 3-day R2 lifecycle delete.

## Delivery (photos to the guest)

- **Upload right away:** after the last shot, upload the color photo and live MP4 to online storage while the strip prints.
- **One private page per session** at a random, hard-to-guess link (e.g. `photos.emporiumthaimarket.com/<random-id>`). No public gallery. The page shows:
  - the color photo with Save
  - the looping live video with Save / Share to Instagram
  - one small link: Order online (Square site)
- **Expiry:** auto-delete after [30–60] days. The text says so.
- **Send the text only after the upload succeeds.** If Wi-Fi drops, queue the session and send when reconnected. Never send a broken link.
- **Texting provider:** RingCentral **High Volume SMS** API (the restaurant already uses RingCentral). It handles STOP/START automatically. It doesn't support MMS, so send **a link, not the video**. Needs 10DLC brand + campaign registration first. Consider a separate number/extension just for the booth.
- **Do NOT** send through iMessage or the iPad's Apple ID. It doesn't reach Android, leaves guests' numbers on the iPad, and can't handle STOP.
- **First text (draft):** Emporium Thai Market: your photobooth pics are ready! [link] (expires in [30] days). Msg & data rates may apply. Reply STOP to opt out, HELP for help.
- **Consent records:** for every signup, store the phone number, timestamp, booth ID and the exact consent text version shown. Delete session media when it expires.

## Still to decide (placeholders above)

- [ ] Max marketing texts per month (the [4])
- [ ] Terms and Privacy page URLs
- [ ] Link expiry: 30 or 60 days
- [ ] Where the photo pages are hosted, and the domain
- [ ] Separate RingCentral number for the booth, or the main line
- [ ] Final frame list (classic, single, seasonal)
- [ ] Auto-return timers (20s on 04, 10s on Sent)
