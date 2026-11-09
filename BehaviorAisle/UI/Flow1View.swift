import SwiftUI
import RealityKit

/// Demo Flow 1 window: handle in, live lane timeline against the 20 s budget, photo scan,
/// body trait meters, affinity radar, interest chips, wishlist and a HumanHD turntable.
struct Flow1View: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openSpace
    @State private var handle = ""

    private var flow: Flow1 { model.flow1 }
    static let blue = Color(hex: 0x1D9BF0)

    var body: some View {
        TimelineView(.animation(paused: !flow.running)) { _ in
            VStack(spacing: 18) {
                inputRow
                BudgetBar(flow: flow)
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 14) {
                        Lanes(flow: flow)
                        PostStream(flow: flow)
                    }
                    .frame(width: 400)
                    VStack(spacing: 14) {
                        HStack(alignment: .top, spacing: 14) {
                            PhotoScan(flow: flow).frame(width: 190, height: 190)
                            HumanStage(flow: flow).frame(height: 190)
                        }
                        BodyMeters(traits: flow.body)
                    }
                    ShopPanel(flow: flow, model: model).frame(width: 320)
                }
                if let e = flow.error { Text(e).font(.callout).foregroundStyle(Theme.alert) }
            }
            .padding(24)
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: flow.lanes)
        .navigationTitle("Demo Flow 1")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { model.showFlow1 = false }
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "at").foregroundStyle(Self.blue)
            TextField("X handle", text: $handle)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(go)
                .frame(maxWidth: 320)
            Button(flow.running ? "Generating" : "Generate", action: go)
                .buttonStyle(.borderedProminent)
                .tint(Self.blue)
                .disabled(handle.isEmpty || flow.running)
            Spacer()
            if flow.finished != nil, flow.traits != nil {
                Button(model.immersiveOpen ? "In the store" : "See them in the store") {
                    model.showFlow1 = false
                    Task { _ = await openSpace(id: StoreSpace.id) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(model.immersiveOpen)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func go() {
        guard !handle.isEmpty, !flow.running else { return }
        flow.run(handle, model: model)
    }
}

// MARK: Budget

private struct BudgetBar: View {
    let flow: Flow1

    var body: some View {
        let t = flow.started == nil ? 0 : flow.elapsed
        let frac = min(1, t / Flow1.budget)
        let over = t > Flow1.budget
        HStack(spacing: 14) {
            Text(String(format: "%.1f s", t))
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(over ? Theme.alert : flow.finished != nil ? Theme.accent : .primary)
                .contentTransition(.numericText())
                .frame(width: 120, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [Flow1View.blue, over ? Theme.alert : Theme.accent], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, g.size.width * frac))
                    ForEach([5.0, 10, 15], id: \.self) { s in
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 14)
                            .offset(x: g.size.width * s / Flow1.budget)
                    }
                }
            }
            .frame(height: 14)
            Text("20 s budget").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Lanes

private struct Lanes: View {
    let flow: Flow1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Flow1.LaneID.allCases) { id in row(id, flow.lane(id)) }
        }
        .padding(16)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
    }

    private func row(_ id: Flow1.LaneID, _ l: Flow1.Lane) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                icon(id, l.state).frame(width: 22)
                Text(id.title).font(.callout.weight(.semibold))
                Spacer()
                if let s = l.start {
                    Text(String(format: "%.1f s", (l.end ?? .now).timeIntervalSince(s)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            gantt(l)
            Text(l.detail.isEmpty ? id.route : l.detail)
                .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
        }
        .opacity(l.state == .waiting ? 0.45 : 1)
    }

    @ViewBuilder private func icon(_ id: Flow1.LaneID, _ s: Flow1.State) -> some View {
        switch s {
        case .waiting: Image(systemName: id.icon).foregroundStyle(.tertiary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .fallback: Image(systemName: "arrow.uturn.down.circle.fill").foregroundStyle(Theme.amber)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.alert)
        }
    }

    /// Bar on the shared 0...20 s axis, so parallel lanes visibly overlap.
    private func gantt(_ l: Flow1.Lane) -> some View {
        GeometryReader { g in
            let t0 = flow.started ?? .now
            let a = l.start.map { $0.timeIntervalSince(t0) } ?? 0
            let b = (l.end ?? .now).timeIntervalSince(t0)
            let w = g.size.width / Flow1.budget
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.06))
                if l.start != nil {
                    Capsule()
                        .fill(color(l.state).gradient)
                        .frame(width: max(6, CGFloat(b - a) * w))
                        .offset(x: CGFloat(a) * w)
                        .shadow(color: color(l.state).opacity(l.state == .running ? 0.8 : 0), radius: 6)
                }
            }
        }
        .frame(height: 6)
    }

    private func color(_ s: Flow1.State) -> Color {
        switch s {
        case .done: Theme.accent
        case .fallback: Theme.amber
        case .failed: Theme.alert
        default: Flow1View.blue
        }
    }
}

// MARK: Posts

/// Posts scroll past while the shopping lane reads them; grocery words light up.
private struct PostStream: View {
    let flow: Flow1
    static let words = ["coffee", "cook", "vegan", "pizza", "snack", "beer", "wine", "bread", "cheese", "protein",
                        "gym", "kids", "breakfast", "tea", "salad", "chips", "dinner", "lunch", "food", "eat", "drink", "fruit"]

    var body: some View {
        let posts = Array((flow.profile?.tweets ?? []).prefix(8))
        VStack(alignment: .leading, spacing: 6) {
            if let p = flow.profile {
                Text(p.name).font(.headline) + Text("  @\(p.handle)").foregroundStyle(.secondary)
                if !p.bio.isEmpty { Text(p.bio).font(.caption).lineLimit(2) }
            }
            ForEach(Array(posts.enumerated()), id: \.offset) { i, tw in
                Text(highlight(tw)).font(.caption2).lineLimit(2)
                    .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.05), in: .rect(cornerRadius: 9))
                    .opacity(scanned(i, posts.count) ? 1 : 0.35)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    /// Reading head sweeps the list while /classify/shop runs.
    private func scanned(_ i: Int, _ n: Int) -> Bool {
        let l = flow.lane(.shop)
        guard let s = l.start else { return false }
        if l.end != nil { return true }
        return Double(i) < Date.now.timeIntervalSince(s) * 1.6
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s.replacingOccurrences(of: "\n", with: " "))
        let lower = s.lowercased().replacingOccurrences(of: "\n", with: " ")
        guard lower.count == a.characters.count else { return a }
        for w in Self.words {
            var from = lower.startIndex
            while let r = lower.range(of: w, range: from..<lower.endIndex) {
                let lo = lower.distance(from: lower.startIndex, to: r.lowerBound)
                let start = a.index(a.startIndex, offsetByCharacters: lo)
                let end = a.index(start, offsetByCharacters: w.count)
                a[start..<end].foregroundColor = Theme.amber
                a[start..<end].font = .caption2.bold()
                from = r.upperBound
            }
        }
        return a
    }
}

// MARK: Photo scan

private struct PhotoScan: View {
    let flow: Flow1

    var body: some View {
        let scanning = flow.lane(.body).state == .running
        ZStack {
            if let s = flow.profile?.avatarUrl, let url = URL(string: s.replacingOccurrences(of: "_normal", with: "_400x400")) {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
            } else {
                Color.white.opacity(0.06)
                Image(systemName: "person.crop.square").font(.system(size: 54)).foregroundStyle(.tertiary)
            }
            if scanning {
                TimelineView(.animation) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, Flow1View.blue.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 40)
                            .offset(y: CGFloat((sin(t * 2.4) + 1) / 2) * (g.size.height - 40))
                        grid.opacity(0.35)
                    }
                }
            }
            if let b = flow.body, b.confidence > 0.2 {
                VStack {
                    Spacer()
                    Text("\(Int(b.age)) · \(b.hairStyle) · \(b.eyeColor) eyes")
                        .font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.55), in: .capsule)
                        .padding(8)
                }
                .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(scanning ? Flow1View.blue : .white.opacity(0.1), lineWidth: 2))
    }

    private var grid: some View {
        Canvas { ctx, size in
            var p = Path()
            stride(from: 0, through: size.width, by: 19).forEach { x in p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }
            stride(from: 0, through: size.height, by: 19).forEach { y in p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }
            ctx.stroke(p, with: .color(Flow1View.blue), lineWidth: 0.5)
        }
    }
}

// MARK: HumanHD turntable

private struct HumanStage: View {
    let flow: Flow1
    @State private var holder = Entity()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.05))
            RealityView { content in
                content.add(holder)
            } update: { _ in
                guard let e = flow.preview, e.parent !== holder else { return }
                holder.children.removeAll()
                let bounds = e.visualBounds(relativeTo: nil)
                let h = max(0.5, bounds.extents.y)
                e.scale = .init(repeating: 0.17 / h)
                e.position = [0, -0.085, 0]
                holder.addChild(e)
            }
            .rotation3DEffect(.degrees(turn), axis: .y)
            if flow.preview == nil {
                VStack(spacing: 8) {
                    if flow.lane(.human).state == .running { ProgressView() }
                    Text(flow.lane(.human).state == .running ? "Building HumanHD" : "HumanHD")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var turn: Double {
        guard let end = flow.lane(.human).end else { return 0 }
        return Date.now.timeIntervalSince(end) * 40
    }
}

// MARK: Body meters

private struct BodyMeters: View {
    let traits: ProfileTraits.Body?

    var body: some View {
        let b = traits ?? .neutral
        let on = traits != nil
        VStack(alignment: .leading, spacing: 8) {
            meter("Age", (b.age - 18) / 67, "\(Int(b.age))", on)
            meter("Height", b.height, pct(b.height), on)
            meter("Build", b.weight, pct(b.weight), on)
            meter("Muscle", b.muscle, pct(b.muscle), on)
            HStack(spacing: 10) {
                swatch("Skin", Color(hue: 0.07, saturation: 0.35 + b.undertone * 0.25, brightness: 0.95 - b.skinTone * 0.7), on)
                swatch("Hair", Color(hex: UInt32(HumanTraitsMapper.hex(b.hairColor) ?? 0x2A1A10)), on)
                Chip(text: on ? b.outfit : "outfit", color: on ? Theme.accent : .secondary)
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
        .animation(.spring(duration: 0.9, bounce: 0.2), value: traits)
    }

    private func pct(_ v: Double) -> String { "\(Int(v * 100))" }

    private func meter(_ name: String, _ v: Double, _ label: String, _ on: Bool) -> some View {
        HStack {
            Text(name).font(.caption).frame(width: 56, alignment: .leading)
            PBar(p: on ? v : 0, color: Flow1View.blue)
            Text(on ? label : "–").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .trailing)
        }
    }

    private func swatch(_ name: String, _ c: Color, _ on: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(on ? c : .white.opacity(0.1)).frame(width: 16, height: 16)
            Text(name).font(.caption)
        }
    }
}

// MARK: Shopping

private struct ShopPanel: View {
    let flow: Flow1
    let model: AppModel

    var body: some View {
        let s = flow.shop
        VStack(alignment: .leading, spacing: 12) {
            Radar(values: Category.allCases.map { s?.affinity[$0.rawValue] ?? 0 }, labels: Category.allCases.map(\.label))
                .frame(height: 210)
                .animation(.spring(duration: 1.1, bounce: 0.25), value: s)
            if let s {
                Flow1Tags(items: s.interests)
                HStack {
                    Text("Price sensitive").font(.caption)
                    PBar(p: s.priceSensitivity, color: Theme.amber)
                    Text("\(s.basketSize) items").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(s.wishlist.enumerated()), id: \.element) { i, id in
                        if let p = model.product(id) {
                            HStack {
                                Text("\(i + 1)").font(.caption.bold()).foregroundStyle(Theme.accent).frame(width: 16)
                                Text(p.name).font(.callout)
                                Spacer()
                                Text(p.price, format: .currency(code: "USD")).font(.caption).foregroundStyle(.secondary)
                            }
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                Text(s.summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 18))
    }
}

/// 8-axis category affinity radar. The polygon animates from the center (RadarShape).
private struct Radar: View {
    let values: [Double]
    let labels: [String]

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let n = labels.count
                for ring in [0.25, 0.5, 0.75, 1.0] {
                    ctx.stroke(RadarShape(values: Array(repeating: ring, count: n)).path(in: CGRect(origin: .zero, size: size)),
                               with: .color(.white.opacity(0.12)), lineWidth: 1)
                }
                for i in 0..<n {
                    ctx.draw(Text(labels[i]).font(.caption2).foregroundStyle(.secondary),
                             at: RadarShape.point(i, n, 1.18, in: CGRect(origin: .zero, size: size)))
                }
            }
            RadarShape(values: values.map { max(0.03, $0) }).fill(Flow1View.blue.opacity(0.35))
            RadarShape(values: values.map { max(0.03, $0) }).stroke(Flow1View.blue, lineWidth: 2)
        }
    }
}

private struct RadarShape: Shape {
    var values: [Double]

    var animatableData: AnimatableVector {
        get { AnimatableVector(values) }
        set { values = newValue.values }
    }

    static func point(_ i: Int, _ n: Int, _ v: Double, in rect: CGRect) -> CGPoint {
        let r = min(rect.width, rect.height) / 2 - 26
        let a = Double(i) / Double(max(1, n)) * 2 * .pi - .pi / 2
        return CGPoint(x: rect.midX + cos(a) * r * v, y: rect.midY + sin(a) * r * v)
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let n = values.count
        guard n > 2 else { return p }
        p.move(to: Self.point(0, n, values[0], in: rect))
        for i in 1..<n { p.addLine(to: Self.point(i, n, values[i], in: rect)) }
        p.closeSubpath()
        return p
    }
}

struct AnimatableVector: VectorArithmetic {
    var values: [Double]
    init(_ v: [Double]) { values = v }
    static var zero: Self { .init([]) }
    private static func zip(_ a: Self, _ b: Self, _ f: (Double, Double) -> Double) -> Self {
        let n = max(a.values.count, b.values.count)
        return .init((0..<n).map { f($0 < a.values.count ? a.values[$0] : 0, $0 < b.values.count ? b.values[$0] : 0) })
    }
    static func + (a: Self, b: Self) -> Self { zip(a, b, +) }
    static func - (a: Self, b: Self) -> Self { zip(a, b, -) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

private struct Flow1Tags: View {
    let items: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tags(items) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { tags(Array(items.prefix(3))) }
                HStack(spacing: 6) { tags(Array(items.dropFirst(3))) }
            }
        }
    }
    private func tags(_ s: [String]) -> some View {
        ForEach(s, id: \.self) { t in
            Text(t).font(.caption.bold())
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Flow1View.blue.opacity(0.25), in: .capsule)
                .transition(.scale.combined(with: .opacity))
        }
    }
}
