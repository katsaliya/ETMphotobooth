import SwiftUI

/// 01 · Pick a frame (home screen) — docs/user-flow.md.
/// Left: live strip preview with arrows, swipe, name and dots.
/// Right: brand mark, headline, frame tiles, "I'm ready".
/// Only the "I'm ready" button starts a session — tapping the preview never does.
struct WelcomeView: View {
    @ObservedObject var camera: CameraCaptureManager
    @ObservedObject var printer: PrintManager
    let onStart: (BoothFrame) -> Void

    @ObservedObject private var frameStore = FrameConfigStore.shared
    @State private var showPrinterManagement = false
    @State private var selectedIndex = 0

    private let frames = BoothFrame.all
    private var selectedFrame: BoothFrame { frames[selectedIndex] }

    var body: some View {
        Boothbackground(backgroundColor: BoothTheme.background) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    previewColumn(size: CGSize(width: geo.size.width / 2, height: geo.size.height))
                        .frame(width: geo.size.width / 2)

                    BoothTheme.divider
                        .frame(width: 1)
                        .padding(.vertical, 56)

                    infoColumn
                        .padding(.horizontal, 56)
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            camera.start()
            printer.autoConnect()
            applySelection()
        }
        .onChange(of: selectedIndex) { applySelection() }
        .sheet(isPresented: $showPrinterManagement) {
            PrinterManagementView(printer: printer)
        }
    }

    // MARK: - Left: live strip preview

    private func previewColumn(size: CGSize) -> some View {
        let arrowSpace: CGFloat = 2 * (52 + 20)
        let maxStripHeight = size.height - 80 - 110 // vertical padding + caption block
        let maxStripWidth = size.width - arrowSpace - 40
        let factor = StripPreview.heightFactor(for: selectedFrame)
        let stripWidth = min(maxStripHeight / factor, maxStripWidth)

        return VStack(spacing: 0) {
            Spacer(minLength: 40)

            HStack(spacing: 20) {
                arrowButton(systemName: "chevron.left") { step(-1) }

                StripPreview(frame: selectedFrame, width: stripWidth, liveSession: camera.session)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onEnded { value in
                                if value.translation.width <= -40 { step(1) }
                                else if value.translation.width >= 40 { step(-1) }
                            }
                    )

                arrowButton(systemName: "chevron.right") { step(1) }
            }

            VStack(spacing: 10) {
                Text(selectedFrame.caption)
                    .font(BoothTheme.body(20, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    ForEach(frames.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == selectedIndex ? Color.black.opacity(0.85) : Color.white.opacity(0.6))
                            .frame(width: index == selectedIndex ? 24 : 9, height: 9)
                    }
                }

                Text(BoothCopy.Home.swipeHint)
                    .font(BoothTheme.body(15))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.top, 22)

            Spacer(minLength: 40)
        }
        .frame(width: size.width, height: size.height)
    }

    private func arrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(BoothTheme.arrowChevron)
                .frame(width: 52, height: 68)
                .contentShape(Ellipse())
        }
        .buttonStyle(.plain)
        // iOS 26 Liquid Glass: frosted, refracts what's behind it, and
        // reacts (shimmer/squish) when pressed.
        .glassEffect(.regular.interactive(), in: Ellipse())
    }

    // MARK: - Right: copy, tiles, start

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand mark, top-left (Figma frame 1). The logo stays the hidden
            // staff entry to printer settings, and dims when disconnected.
            HStack(spacing: 12) {
                let isConnected = printer.connectedPrinter != nil
                Button { showPrinterManagement = true } label: {
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 37)
                        .grayscale(isConnected ? 0 : 1)
                        .opacity(isConnected ? 1 : 0.6)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.easeInOut, value: isConnected)

                Text(BoothCopy.Home.brandLabel)
                    .font(BoothTheme.label(15))
                    .tracking(3)
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 20)

            Text("\(BoothCopy.Home.headlineLead)\(Text(BoothCopy.Home.headlineAccent).italic().foregroundStyle(.white))")
                .font(BoothTheme.headline(68))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(BoothCopy.Home.sub)
                .font(BoothTheme.body(20).italic())
                .foregroundStyle(.white)
                .frame(maxWidth: 360, alignment: .leading)
                .padding(.top, 8)

            Text(BoothCopy.Home.chooseLabel)
                .font(BoothTheme.label(15))
                .tracking(2)
                .foregroundStyle(.white)
                .padding(.top, 40)

            HStack(spacing: 14) {
                ForEach(frames.indices, id: \.self) { index in
                    frameTile(index: index)
                }
            }
            .padding(.top, 12)

            // Hint sits under the tiles in Figma frame 1.
            Text(BoothCopy.Home.chooseHint)
                .font(BoothTheme.body(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 10)

            Button { onStart(selectedFrame) } label: {
                Text(camera.isRunningSequence ? BoothCopy.Home.startButtonBusy : BoothCopy.Home.startButton)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 300, height: 68)
                    .background(Capsule().fill(BoothTheme.primaryButton))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            // A cancelled session's camera sequence may still be finishing;
            // starting again before it ends would be silently ignored.
            .disabled(camera.isRunningSequence)
            .opacity(camera.isRunningSequence ? 0.6 : 1)
            .padding(.top, 36)

            Text(BoothCopy.Home.footer)
                .font(BoothTheme.body(17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            Spacer(minLength: 20)
        }
    }

    private func frameTile(index: Int) -> some View {
        let frame = frames[index]
        let isSelected = index == selectedIndex
        let thumbHeight: CGFloat = 130

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedIndex = index }
        } label: {
            VStack(spacing: 10) {
                StripPreview(frame: frame, width: thumbHeight / StripPreview.heightFactor(for: frame))
                    .frame(height: thumbHeight)
                Text(frame.name)
                    .font(BoothTheme.body(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(BoothTheme.tileFill))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white, lineWidth: isSelected ? 1.5 : 0)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection

    private func step(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedIndex = (selectedIndex + delta + frames.count) % frames.count
        }
    }

    /// Hands the chosen frame's print layout to the existing config so
    /// Capture takes the right number of shots and StripComposer uses the
    /// right template. Only writes when it actually changes.
    private func applySelection() {
        let mode = selectedFrame.templateMode
        if frameStore.config.resolvedTemplateMode != mode {
            frameStore.config.templateMode = mode
        }
    }
}

#Preview {
    WelcomeView(camera: CameraCaptureManager(), printer: PrintManager(), onStart: { _ in })
}
