//
//  ContentView.swift
//  SketchFade
//
//  Created by Matt Popovich on 3/11/26.
//

import SwiftUI
internal import Combine

// MARK: - Brush Types

enum BrushType: String, CaseIterable, Identifiable {
    case pencil      = "Pencil"
    case crayon      = "Crayon"
    case sharpie     = "Sharpie"
    case highlighter = "Highlighter"
    case inkBlob     = "Ink Blob"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pencil:      return "pencil"
        case .crayon:      return "pencil.tip"
        case .sharpie:     return "paintbrush.pointed.fill"
        case .highlighter: return "highlighter"
        case .inkBlob:     return "drop.fill"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .pencil:      return 2.5
        case .crayon:      return 10.0
        case .sharpie:     return 5.5
        case .highlighter: return 26.0
        case .inkBlob:     return 15.0
        }
    }

    var baseOpacity: Double {
        switch self {
        case .pencil:      return 0.85
        case .crayon:      return 0.70
        case .sharpie:     return 1.00
        case .highlighter: return 0.38
        case .inkBlob:     return 0.95
        }
    }
}

// MARK: - Stroke Model

struct Stroke: Identifiable {
    let id        = UUID()
    var points    : [CGPoint]
    var color     : Color
    var brush     : BrushType
    var createdAt : Date
    var opacity   : Double = 1.0
}

// MARK: - Drawing Canvas

struct DrawingCanvas: View {
    let strokes       : [Stroke]
    let currentStroke : Stroke?
    let onStart       : (CGPoint) -> Void
    let onMove        : (CGPoint) -> Void
    let onEnd         : ()        -> Void

    var body: some View {
        Canvas { ctx, _ in
            for s in strokes       { render(s, in: &ctx) }
            if let s = currentStroke { render(s, in: &ctx) }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if v.translation == .zero { onStart(v.location) }
                    else                      { onMove(v.location)  }
                }
                .onEnded { _ in onEnd() }
        )
    }

    // MARK: Rendering

    private func render(_ stroke: Stroke, in ctx: inout GraphicsContext) {
        let pts = stroke.points
        guard !pts.isEmpty else { return }

        // Single tap → dot
        if pts.count == 1 {
            let r = stroke.brush.lineWidth / 2
            let rect = CGRect(x: pts[0].x - r, y: pts[0].y - r, width: r*2, height: r*2)
            var c = ctx
            c.opacity = stroke.opacity * stroke.brush.baseOpacity
            c.fill(Path(ellipseIn: rect), with: .color(stroke.color))
            return
        }

        switch stroke.brush {
        case .pencil:      renderPencil(stroke,      pts: pts, in: &ctx)
        case .crayon:      renderCrayon(stroke,      pts: pts, in: &ctx)
        case .sharpie:     renderSharpie(stroke,     pts: pts, in: &ctx)
        case .highlighter: renderHighlighter(stroke, pts: pts, in: &ctx)
        case .inkBlob:     renderInkBlob(stroke,     pts: pts, in: &ctx)
        }
    }

    // Smooth quadratic-spline path
    private func spline(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.move(to: pts[0])
        guard pts.count > 2 else { p.addLine(to: pts.last!); return p }
        for i in 1..<pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i+1].x) / 2,
                              y: (pts[i].y + pts[i+1].y) / 2)
            p.addQuadCurve(to: mid, control: pts[i])
        }
        p.addLine(to: pts.last!)
        return p
    }

    // ── Pencil: thin, slightly scratchy
    private func renderPencil(_ s: Stroke, pts: [CGPoint], in ctx: inout GraphicsContext) {
        let path = spline(pts)
        var c = ctx; c.opacity = s.opacity * s.brush.baseOpacity
        c.stroke(path, with: .color(s.color),
                 style: StrokeStyle(lineWidth: s.brush.lineWidth, lineCap: .round, lineJoin: .round))
        // Light secondary pass for texture
        var c2 = ctx; c2.opacity = s.opacity * 0.25
        c2.stroke(path, with: .color(s.color),
                  style: StrokeStyle(lineWidth: s.brush.lineWidth * 0.35, lineCap: .round,
                                     lineJoin: .round, dash: [1.5, 5]))
    }

    // ── Crayon: waxy multi-layer texture
    private func renderCrayon(_ s: Stroke, pts: [CGPoint], in ctx: inout GraphicsContext) {
        let path = spline(pts)
        let layers: [(CGFloat, CGFloat, Double)] = [
            ( 0,    0,   0.60),
            ( 1.2,  0.8, 0.38),
            (-1.0,  0,   0.32),
            ( 0,   -1.5, 0.28),
            ( 1.8, -0.8, 0.20),
        ]
        for (dx, dy, alpha) in layers {
            var c = ctx; c.opacity = s.opacity * alpha
            c.translateBy(x: dx, y: dy)
            c.stroke(path, with: .color(s.color),
                     style: StrokeStyle(lineWidth: s.brush.lineWidth * 0.88,
                                        lineCap: .round, lineJoin: .round))
        }
    }

    // ── Sharpie: bold, opaque, clean
    private func renderSharpie(_ s: Stroke, pts: [CGPoint], in ctx: inout GraphicsContext) {
        let path = spline(pts)
        var c = ctx; c.opacity = s.opacity * s.brush.baseOpacity
        c.stroke(path, with: .color(s.color),
                 style: StrokeStyle(lineWidth: s.brush.lineWidth, lineCap: .round, lineJoin: .round))
    }

    // ── Highlighter: wide, transparent, flat-cap
    private func renderHighlighter(_ s: Stroke, pts: [CGPoint], in ctx: inout GraphicsContext) {
        let path = spline(pts)
        var c = ctx
        c.opacity    = s.opacity * s.brush.baseOpacity
        c.blendMode  = .multiply
        c.stroke(path, with: .color(s.color),
                 style: StrokeStyle(lineWidth: s.brush.lineWidth, lineCap: .square, lineJoin: .round))
    }

    // ── Ink Blob: variable width (fast = thin), ink puddle at start
    private func renderInkBlob(_ s: Stroke, pts: [CGPoint], in ctx: inout GraphicsContext) {
        var c = ctx; c.opacity = s.opacity * s.brush.baseOpacity
        for i in 1..<pts.count {
            let p1  = pts[i-1], p2 = pts[i]
            let dist = hypot(p2.x - p1.x, p2.y - p1.y)
            let speed = min(dist, 28.0)
            let w = s.brush.lineWidth * (1.0 - speed / 55.0) + 5.0
            var seg = Path(); seg.move(to: p1); seg.addLine(to: p2)
            c.stroke(seg, with: .color(s.color),
                     style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        // Ink blob at origin
        if let first = pts.first {
            let blob = s.brush.lineWidth * 2.0
            let rect = CGRect(x: first.x - blob/2, y: first.y - blob/2, width: blob, height: blob)
            c.fill(Path(ellipseIn: rect), with: .color(s.color))
        }
    }
}

// MARK: - Color Palette

struct ColorPaletteView: View {
    @Binding var selectedColor: Color

    private let presets: [Color] = [
        .black, .white,
        Color(red:0.90, green:0.10, blue:0.10),  // Red
        Color(red:1.00, green:0.50, blue:0.00),  // Orange
        Color(red:0.95, green:0.85, blue:0.00),  // Yellow
        Color(red:0.10, green:0.72, blue:0.20),  // Green
        Color(red:0.10, green:0.45, blue:0.90),  // Blue
        Color(red:0.55, green:0.10, blue:0.85),  // Purple
        Color(red:0.95, green:0.30, blue:0.65),  // Pink
        Color(red:0.50, green:0.28, blue:0.10),  // Brown
        Color(red:0.00, green:0.55, blue:0.55),  // Teal
        Color(red:0.80, green:0.10, blue:0.30),  // Crimson
        Color(red:0.00, green:0.30, blue:0.55),  // Navy
        Color(red:0.60, green:0.80, blue:0.20),  // Lime
        Color(red:0.85, green:0.65, blue:0.90),  // Lavender
        Color(red:0.40, green:0.40, blue:0.40),  // Gray
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Native color picker
                ColorPicker("", selection: $selectedColor)
                    .labelsHidden()
                    .frame(width: 34, height: 34)
                    .scaleEffect(1.1)

                // Preset swatches
                ForEach(presets, id: \.self) { color in
                    Button { selectedColor = color } label: {
                        ZStack {
                            Circle().fill(color).frame(width: 30, height: 30)
                            Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                .frame(width: 30, height: 30)
                            if isSelected(color) {
                                Circle().stroke(Color.accentColor, lineWidth: 3)
                                    .frame(width: 34, height: 34)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func isSelected(_ color: Color) -> Bool {
        UIColor(color) == UIColor(selectedColor)
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Binding var backgroundColor : Color
    @Binding var fadeDuration    : Double
    @Environment(\.dismiss) private var dismiss

    private let bgPresets: [(String, Color)] = [
        ("White",      .white),
        ("Black",      Color(white: 0.08)),
        ("Parchment",  Color(red:0.96, green:0.93, blue:0.84)),
        ("Midnight",   Color(red:0.12, green:0.12, blue:0.22)),
        ("Sky Blue",   Color(red:0.82, green:0.92, blue:0.99)),
        ("Sage",       Color(red:0.82, green:0.90, blue:0.82)),
    ]

    var body: some View {
        NavigationStack {
            Form {
                // ── Background
                Section {
                    ColorPicker("Custom Color", selection: $backgroundColor)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                        ForEach(bgPresets, id: \.0) { name, color in
                            Button {
                                backgroundColor = color
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(color)
                                        .frame(height: 44)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(UIColor(color) == UIColor(backgroundColor)
                                                        ? Color.accentColor : Color.gray.opacity(0.4),
                                                        lineWidth: UIColor(color) == UIColor(backgroundColor) ? 2.5 : 1)
                                        )
                                    Text(name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: { Text("Canvas Background") }

                // ── Fade Timer
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Fade Duration", systemImage: "timer")
                            Spacer()
                            Text("\(Int(fadeDuration)) sec")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .bold()
                        }

                        Slider(value: $fadeDuration, in: 1...60, step: 1)
                            .tint(.accentColor)

                        HStack {
                            Text("1s").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("60s").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    // Quick-pick buttons
                    HStack(spacing: 8) {
                        ForEach([3, 5, 10, 15, 30], id: \.self) { sec in
                            Button("\(sec)s") { fadeDuration = Double(sec) }
                                .buttonStyle(.bordered)
                                .tint(Int(fadeDuration) == sec ? .accentColor : .gray)
                                .font(.subheadline.bold())
                        }
                    }
                    .padding(.vertical, 2)
                } header: { Text("Fade Timer") }
                  footer: { Text("Strokes will fade from full opacity to invisible over this duration.") }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: { dismiss() }).bold()
                }
            }
        }
    }
}

// MARK: - Main View

struct ContentView: View {
    @State private var strokes            : [Stroke]   = []
    @State private var currentStroke      : Stroke?    = nil
    @State private var bgColor            : Color      = .white
    @State private var penColor           : Color      = .black
    @State private var brush              : BrushType  = .pencil
    @State private var fadeDuration       : Double     = 5.0
    @State private var showSettings       : Bool       = false
    @State private var showClearAlert     : Bool       = false
    @State private var strokeCount        : Int        = 0
    @State private var showResetCountAlert: Bool       = false
    @State private var counterBump        : Bool       = false

    private let fps: Double = 30

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Background
            bgColor.ignoresSafeArea()

            // ── Canvas
            DrawingCanvas(
                strokes: strokes,
                currentStroke: currentStroke,
                onStart: { pt in
                    currentStroke = Stroke(points: [pt], color: penColor,
                                           brush: brush, createdAt: Date())
                },
                onMove: { pt in currentStroke?.points.append(pt) },
                onEnd:  {
                    if let s = currentStroke { strokes.append(s) }
                    currentStroke = nil
                    strokeCount += 1
                    withAnimation(.interpolatingSpring(stiffness: 600, damping: 12)) {
                        counterBump = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        counterBump = false
                    }
                }
            )
            .ignoresSafeArea()

            // ── Bottom Panel
            VStack(spacing: 0) {
                // Brush row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(BrushType.allCases) { b in
                            Button {
                                brush = b
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: b.icon).font(.system(size: 13))
                                    Text(b.rawValue).font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 9)
                                .background(brush == b ? penColor : Color(.systemGray5))
                                .foregroundStyle(brush == b ? contrastColor(penColor) : Color.primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }

                // Color palette
                ColorPaletteView(selectedColor: $penColor)
                    .padding(.bottom, 6)
            }
            .background(.ultraThinMaterial)

            // ── Top Bar (overlaid)
            VStack {
                HStack(alignment: .top, spacing: 10) {

                    // Settings
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    // Centre column: timer + stroke counter stacked
                    VStack(spacing: 6) {

                        // Fade timer badge
                        HStack(spacing: 5) {
                            Image(systemName: "timer").font(.caption.weight(.semibold))
                            Text("\(Int(fadeDuration))s").font(.caption.monospacedDigit().bold())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())

                        // Stroke counter badge + reset button side-by-side
                        HStack(spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.caption.weight(.semibold))
                                Text("\(strokeCount)")
                                    .font(.caption.monospacedDigit().bold())
                                    .contentTransition(.numericText())
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .scaleEffect(counterBump ? 1.25 : 1.0)

                            // Reset counter button
                            Button {
                                showResetCountAlert = true
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.caption.weight(.bold))
                                    .padding(7)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                        }
                    }

                    Spacer()

                    // Clear canvas
                    Button { showClearAlert = true } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .medium))
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        // ── Fade timer
        .onReceive(
            Timer.publish(every: 1.0 / fps, on: .main, in: .common).autoconnect()
        ) { _ in tick() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(backgroundColor: $bgColor, fadeDuration: $fadeDuration)
        }
        .alert("Clear Canvas?", isPresented: $showClearAlert) {
            Button("Clear", role: .destructive) { strokes.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Reset Counter?", isPresented: $showResetCountAlert) {
            Button("Reset", role: .destructive) { strokeCount = 0 }
            Button("Cancel", role: .cancel) {}
        }
    }

    // Fade and cull strokes each frame
    private func tick() {
        let now = Date()
        strokes = strokes.compactMap { s in
            let age = now.timeIntervalSince(s.createdAt)
            guard age < fadeDuration else { return nil }
            var updated = s
            updated.opacity = max(0, 1.0 - (age / fadeDuration))
            return updated
        }
    }

    // Pick white or black to contrast against a given fill
    private func contrastColor(_ color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
        return (0.299*r + 0.587*g + 0.114*b) > 0.55 ? .black : .white
    }
}

// MARK: - Preview
#Preview { ContentView() }
