import SwiftUI

/// X profile import: handle field, animated analysis (scan ring, post ticker, trait chips,
/// affinity bars), then the predicted products and a jump into the store.
struct ProfileImportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openImmersiveSpace) private var openSpace
    @State private var handle = ""
    @State private var spin = false
    @State private var shownPosts = 0
    @State private var shownChips = 0

    private static let accent = Color(hex: 0x1D9BF0)

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if !busy && model.importStage != .done { HStack {
                    TextField("@handle", text: $handle)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onSubmit(start)
                    Button("Analyze", action: start)
                        .buttonStyle(.borderedProminent)
                        .disabled(handle.isEmpty || busy)
                } }
                if model.importStage != .idle {
                    scanner
                    if model.importStage != .done { stages }
                }
                if let p = model.importedProfile, stageIndex >= 1, model.importedTraits == nil { posts(p) }
                if let t = model.importedTraits { traits(t) }
                if case .failed(let msg) = model.importStage {
                    Text(msg).font(.callout).foregroundStyle(.red)
                }
            }
            .padding(24)
            .animation(.spring(duration: 0.5, bounce: 0.3), value: model.importStage)
        }
        .navigationTitle(model.importedProfile.map { "@\($0.handle)" } ?? "Profile analysis")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { model.showAnalysis = false }
            }
        }
        .onChange(of: model.importStage) { _, s in
            if s == .reading { revealPosts() }
            if s == .building || s == .done { revealChips() }
        }
    }

    private var busy: Bool {
        switch model.importStage {
        case .fetching, .reading, .classifying, .building: true
        default: false
        }
    }

    private var stageIndex: Int {
        switch model.importStage {
        case .idle, .failed: -1
        case .fetching: 0
        case .reading: 1
        case .classifying: 2
        case .building: 3
        case .done: 4
        }
    }

    private func start() {
        shownPosts = 0
        shownChips = 0
        model.importProfile(handle)
    }

    // MARK: Scanner

    private var scanner: some View {
        ZStack {
            Circle()
                .stroke(AngularGradient(colors: [Self.accent.opacity(0), Self.accent, .white, Self.accent.opacity(0)], center: .center), lineWidth: 5)
                .frame(width: 168, height: 168)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .opacity(busy ? 1 : 0)
            ForEach(0..<3) { i in
                Circle().stroke(Self.accent.opacity(0.35), lineWidth: 1)
                    .frame(width: 168, height: 168)
                    .scaleEffect(busy ? 1.5 : 1)
                    .opacity(busy ? 0 : 0.6)
                    .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(i) * 0.66), value: busy)
            }
            avatar
                .frame(width: 148, height: 148)
                .clipShape(Circle())
                .overlay { scanLine.clipShape(Circle()) }
            if model.importStage == .done {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36)).foregroundStyle(.white, Self.accent)
                    .offset(x: 58, y: 58)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 220)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let s = model.importedProfile?.avatarUrl, let url = URL(string: s.replacingOccurrences(of: "_normal", with: "_400x400")) {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
        } else {
            let initials = (model.importedProfile?.name ?? "").split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
            ZStack {
                LinearGradient(colors: [Self.accent, Color(hex: 0x7856FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if initials.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: 64)).foregroundStyle(.white.opacity(0.85))
                } else {
                    Text(initials).font(.system(size: 56, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
        }
    }

    private var scanLine: some View {
        TimelineView(.animation(paused: !busy)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                LinearGradient(colors: [.clear, Self.accent.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
                    .offset(y: CGFloat((sin(t * 2.2) + 1) / 2) * (g.size.height - 36))
            }
            .opacity(busy ? 1 : 0)
        }
    }

    // MARK: Stages

    private var stages: some View {
        let names = ["Fetching profile", "Reading posts", "Classifying traits", "Building shopper"]
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(names.indices, id: \.self) { i in
                HStack(spacing: 10) {
                    ZStack {
                        if i < stageIndex {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Self.accent)
                        } else if i == stageIndex {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 22)
                    Text(names[i]).font(.title3).foregroundStyle(i <= stageIndex ? .primary : .tertiary)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Posts

    private func posts(_ p: TwitterProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.name).font(.headline) + Text("  @\(p.handle)").foregroundStyle(.secondary)
            if !p.bio.isEmpty { Text(p.bio).font(.callout) }
            ForEach(Array(p.tweets.prefix(shownPosts).enumerated()), id: \.offset) { _, tw in
                Text(tw).font(.caption).lineLimit(2)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: .rect(cornerRadius: 10))
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func revealPosts() {
        let n = min(model.importedProfile?.tweets.count ?? 0, 6)
        for i in 0..<n {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(i) * 0.35) {
                withAnimation(.spring(duration: 0.4)) { shownPosts = i + 1 }
            }
        }
    }

    // MARK: Traits

    private func traits(_ t: ProfileTraits) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FlowChips(items: Array(t.interests.prefix(shownChips)), color: Self.accent)
            Text(t.summary).font(.callout).foregroundStyle(.secondary)
            ForEach(Category.allCases, id: \.self) { c in
                let v = t.affinity[c.rawValue] ?? 0
                HStack {
                    Text(c.label).font(.caption).frame(width: 78, alignment: .leading)
                    GeometryReader { g in
                        Capsule().fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Self.accent.gradient)
                                    .frame(width: g.size.width * CGFloat(shownChips > 0 ? v : 0))
                            }
                    }
                    .frame(height: 6)
                }
            }
            .animation(.spring(duration: 0.9, bounce: 0.2), value: shownChips)
            if !t.wishlist.isEmpty {
                Text("Likely to buy").font(.headline)
                ForEach(t.wishlist, id: \.self) { id in
                    if let p = model.product(id) {
                        HStack {
                            Text(p.name)
                            Spacer()
                            Text(p.price, format: .currency(code: "USD")).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
            if model.importStage == .done {
                Button(model.immersiveOpen ? "Shopper is in the store" : "See them in the store") {
                    model.showAnalysis = false
                    Task { _ = await openSpace(id: StoreSpace.id) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.immersiveOpen)
                .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func revealChips() {
        let n = model.importedTraits?.interests.count ?? 0
        for i in 0...max(0, n - 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.18) {
                withAnimation(.spring(duration: 0.35, bounce: 0.5)) { shownChips = max(shownChips, i + 1) }
            }
        }
    }
}

/// Wrapping row of capsule tags.
private struct FlowChips: View {
    let items: [String]
    let color: Color

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { s in
                Text(s).font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(color.opacity(0.25), in: .capsule)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
