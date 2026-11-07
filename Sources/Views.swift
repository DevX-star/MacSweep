// Views.swift — 界面
// 注意：Xcode 命令行工具缺少 SwiftUI 宏插件，所以不使用 @State / #Preview，状态都放在 ObservableObject 中。

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 根视图

struct RootView: View {
    @StateObject private var app = AppState()
    @StateObject private var sweep = SweepModel()
    @StateObject private var large = LargeFileModel()
    @StateObject private var uninstall = UninstallModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $app.pane) {
                Section(t("工具")) {
                    ForEach(Pane.allCases) { p in
                        Label { Text(p.title) } icon: { IconTile(symbol: p.icon, color: p.color, size: 22) }
                            .tag(p)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) { SidebarDisk(app: app) }
        } detail: {
            Group {
                switch app.pane ?? .clean {
                case .clean: CleanView(app: app, vm: sweep)
                case .large: LargeFilesView(app: app, vm: large)
                case .uninstall: UninstallView(app: app, vm: uninstall)
                }
            }
            .id(app.lang)   // 切换语言时重建详情页，所有文字立即更新
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BackgroundLayer(app: app))
        }
        .frame(minWidth: 860, minHeight: 600)
        .onChange(of: app.lang) { _ in
            sweep.refreshIdleStatus(); large.refreshIdleStatus(); uninstall.refreshIdleStatus()
        }
        // 直接把图片拖进窗口即可设为背景
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { app.setBackground(from: url) }
            }
            return true
        }
    }
}

struct SidebarDisk: View {
    @ObservedObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
                Text("Macintosh HD").font(.caption.bold())
            }
            SizeBar(ratio: app.usedRatio, color: diskColor(app.usedRatio), width: nil)
            Text(t("可用 %@", "\(fmt(app.disk.free))")).font(.caption2).foregroundStyle(.secondary)
            if app.totalFreed > 0 {
                Text(t("累计释放 %@", "\(fmt(app.totalFreed))")).font(.caption2).foregroundStyle(.green)
            }
            Divider().padding(.vertical, 2)
            Button { app.showAppearance.toggle() } label: {
                Label(t("设置"), systemImage: "gearshape").font(.caption)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $app.showAppearance, arrowEdge: .trailing) { AppearancePanel(app: app) }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }
}

// MARK: - 背景

struct BackgroundLayer: View {
    @ObservedObject var app: AppState
    var body: some View {
        if let img = app.bgImage {
            GeometryReader { g in
                Image(nsImage: img).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height).clipped()
                    .blur(radius: app.bgBlur, opaque: true)
            }
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(app.bgDim))
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }
}

struct AppearancePanel: View {
    @ObservedObject var app: AppState
    private let width: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(t("语言"), icon: "globe") {
                Picker("", selection: $app.lang) {
                    ForEach(Lang.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Divider()

            section(t("背景图"), icon: "photo") {
                // 用固定尺寸的占位框 + overlay，避免 scaledToFill 的图片撑大布局
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .overlay {
                        if let img = app.bgImage {
                            Image(nsImage: img).resizable().scaledToFill()
                                .blur(radius: app.bgBlur / 3, opaque: true)
                                .overlay(Color(nsColor: .windowBackgroundColor).opacity(app.bgDim))
                        } else {
                            ZStack {
                                Rectangle().fill(.quaternary)
                                Label(t("未设置"), systemImage: "photo").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.quaternary))

                HStack {
                    Button { app.chooseBackground() } label: {
                        Label(t("上传图片…"), systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Button(t("移除")) { app.clearBackground() }.disabled(app.bgImage == nil)
                    Spacer(minLength: 0)
                }
                Text(t("也可以直接把图片拖进窗口")).font(.caption).foregroundStyle(.secondary)

                if app.bgImage != nil {
                    slider(t("遮罩"), value: $app.bgDim, range: 0...0.9)
                    slider(t("模糊"), value: $app.bgBlur, range: 0...30)
                    Text(t("遮罩越高，文字越清晰")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section<C: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 64, alignment: .leading).lineLimit(1)
            Slider(value: value, in: range)
        }
    }
}

// MARK: - 通用组件

func diskColor(_ r: Double) -> Color { r > 0.9 ? .red : r > 0.75 ? .orange : .accentColor }

struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct SizeBar: View {
    let ratio: Double
    let color: Color
    var width: CGFloat? = 90
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            GeometryReader { g in
                Capsule().fill(color.gradient).frame(width: max(4, g.size.width * min(max(ratio, 0), 1)))
            }
        }
        .frame(width: width, height: 6)
        .frame(maxWidth: width == nil ? .infinity : nil)
    }
}

struct Ring: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle().trim(from: 0, to: value)
                .stroke(AngularGradient(colors: [color.opacity(0.6), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.6), value: value)
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.medium)).padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(color).background(color.opacity(0.14), in: Capsule())
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
    }
}

struct RevealButton: View {
    let url: URL
    var body: some View {
        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
            Image(systemName: "magnifyingglass")
        }
        .buttonStyle(.borderless).help(t("在访达中显示"))
    }
}

/// 底部操作栏
struct ActionBar<Trailing: View>: View {
    let status: String
    let busy: Bool
    var progress: Double? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            if busy {
                if let progress { ProgressView(value: progress).frame(width: 80) }
                else { ProgressView().controlSize(.small) }
            }
            Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            trailing
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }
}

// MARK: - 智能清理

struct CleanView: View {
    @ObservedObject var app: AppState
    @ObservedObject var vm: SweepModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    if vm.scanned { results } else { ruleGrid }
                }
                .padding(20)
            }
            ActionBar(status: vm.status, busy: vm.busy, progress: vm.busy && !vm.scanned ? vm.progress : nil) {
                if vm.scanned {
                    Button(t("返回")) { withAnimation { vm.reset() } }.disabled(vm.busy)
                    Button(t("清理 %@", "\(fmt(vm.selectedSize))")) { vm.showConfirm = true }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(vm.selectedSize == 0 || vm.busy)
                }
            }
        }
        .navigationTitle(t("智能清理"))
        .alert(t("确认清理 %@？", "\(fmt(vm.selectedSize))"), isPresented: $vm.showConfirm) {
            Button(t("取消"), role: .cancel) {}
            Button(t("清理"), role: .destructive) { vm.clean(app: app) }
        } message: {
            Text(vm.includesPermanent ? t("废纸篓中的内容将被永久删除，无法恢复；其余项目会移到废纸篓。")
                                      : t("所选项目将移到废纸篓，需要时可以恢复。建议先退出相关应用。"))
        }
    }

    private var hero: some View {
        Card {
            HStack(spacing: 24) {
                ZStack {
                    Ring(value: app.usedRatio, color: diskColor(app.usedRatio))
                    VStack(spacing: 2) {
                        Text("\(Int(app.usedRatio * 100))%").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(t("已使用")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 8) {
                    if vm.scanned {
                        Text(fmt(vm.total)).font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.tint).contentTransition(.numericText())
                        Text(t("可清理空间 · 已勾选 %@", "\(fmt(vm.selectedSize))")).foregroundStyle(.secondary)
                    } else if let last = app.lastFreed {
                        Label(t("清理完成"), systemImage: "checkmark.seal.fill").font(.title2.bold()).foregroundStyle(.green)
                        Text(t("刚刚释放了 %@，移到废纸篓的内容可以恢复", "\(fmt(last))")).foregroundStyle(.secondary)
                    } else {
                        Text(t("让你的 Mac 保持轻盈")).font(.title2.bold())
                        Text(t("可用 %@ / 共 %@", "\(fmt(app.disk.free))", "\(fmt(app.disk.total))")).foregroundStyle(.secondary)
                    }
                    if !vm.scanned {
                        Button { vm.scan() } label: {
                            Label(vm.busy ? t("扫描中…") : t("开始扫描"), systemImage: "magnifyingglass")
                                .frame(minWidth: 120)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(vm.busy || vm.enabled.isEmpty)
                        .padding(.top, 4)
                    }
                }
                Spacer()
            }
        }
    }

    private var ruleGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("扫描范围")).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(allRules) { rule in
                    let on = vm.enabled.contains(rule.id)
                    Button { withAnimation(.easeOut(duration: 0.15)) { vm.toggleRule(rule.id) } } label: {
                        HStack(spacing: 12) {
                            IconTile(symbol: rule.icon, color: on ? rule.color : .gray, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(rule.desc).font(.caption).lineLimit(2)
                                    .foregroundStyle(rule.permanent ? .red : .secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(on ? AnyShapeStyle(rule.color) : AnyShapeStyle(.tertiary))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .background(on ? AnyShapeStyle(rule.color.opacity(0.10)) : AnyShapeStyle(Color.clear),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(on ? rule.color.opacity(0.5) : Color.secondary.opacity(0.2)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var results: some View {
        VStack(spacing: 10) {
            ForEach(vm.results) { r in
                Card { CategoryRow(r: r, vm: vm, maxTotal: vm.maxCategory) }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct CategoryRow: View {
    let r: CategoryResult
    @ObservedObject var vm: SweepModel
    let maxTotal: Int64
    @StateObject private var ui = Expand()

    final class Expand: ObservableObject { @Published var open = false }

    var body: some View {
        let selCount = r.items.lazy.filter { vm.selected.contains($0.url) }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { selCount == r.items.count }, set: { vm.setAll(r.items, $0) }))
                    .labelsHidden().toggleStyle(.checkbox)
                IconTile(symbol: r.rule.icon, color: r.rule.color, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(r.rule.title).font(.headline)
                        if r.rule.permanent { Tag(text: t("永久删除"), color: .red) }
                    }
                    Text(t("已选 %@/%@ 项", "\(selCount)", "\(r.items.count)")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SizeBar(ratio: Double(r.total) / Double(max(maxTotal, 1)), color: r.rule.color)
                Text(fmt(r.total)).font(.body.monospacedDigit().weight(.semibold)).frame(width: 80, alignment: .trailing)
                Button { withAnimation(.easeInOut(duration: 0.2)) { ui.open.toggle() } } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(ui.open ? 90 : 0))
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
            if ui.open {
                Divider()
                ForEach(r.items.prefix(100)) { item in
                    HStack(spacing: 8) {
                        Toggle("", isOn: vm.binding(item.url)).labelsHidden().toggleStyle(.checkbox)
                        Text(displayName(item.url)).lineLimit(1).truncationMode(.middle).help(item.url.path)
                        if item.inUse { Tag(text: t("运行中"), color: .orange) }
                        Spacer()
                        Text(fmt(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        RevealButton(url: item.url)
                    }
                    .padding(.leading, 30)
                }
                if r.items.count > 100 {
                    Text(t("另有 %@ 个较小项目", "\(r.items.count - 100)")).font(.caption).foregroundStyle(.secondary)
                        .padding(.leading, 30)
                }
            }
        }
    }

    /// 通配符规则下（如 Application Support/Slack/Cache/xxx）显示“Slack › xxx”
    private func displayName(_ url: URL) -> String {
        let c = url.pathComponents
        if let i = c.firstIndex(of: "Application Support"), i + 1 < c.count - 1 {
            return "\(c[i + 1]) › \(url.lastPathComponent)"
        }
        return url.lastPathComponent
    }
}

// MARK: - 大文件

struct LargeFilesView: View {
    @ObservedObject var app: AppState
    @ObservedObject var vm: LargeFileModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(t("最小"), selection: $vm.thresholdMB) {
                    Text("100 MB").tag(100); Text("500 MB").tag(500)
                    Text("1 GB").tag(1000); Text("5 GB").tag(5000)
                }
                .pickerStyle(.segmented).frame(width: 300)
                Button { vm.scan() } label: { Label(t("查找"), systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent).disabled(vm.busy)
                Spacer()
                if vm.scanned {
                    TextField(t("筛选路径"), text: $vm.query).textFieldStyle(.roundedBorder).frame(width: 180)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()

            if !vm.scanned {
                EmptyState(icon: "doc.viewfinder", color: .orange, title: t("找出占空间的大文件"),
                           message: t("扫描主目录中的视频、安装包、压缩包等大文件。\n不会自动勾选任何文件，请自行确认后再删除。"))
            } else if vm.files.isEmpty {
                EmptyState(icon: "checkmark.circle", color: .green, title: t("没有找到大文件"), message: t("试试降低大小阈值"))
            } else {
                let maxSize = vm.files.first?.size ?? 1
                List(vm.visible) { f in
                    HStack(spacing: 10) {
                        Toggle("", isOn: vm.binding(f.url)).labelsHidden().toggleStyle(.checkbox)
                        Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path))
                            .resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Text(f.url.deletingLastPathComponent().path.replacingOccurrences(of: Engine.home.path, with: "~"))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                        .help(f.url.path)
                        Spacer()
                        if let d = f.modified {
                            Text(d, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                        }
                        SizeBar(ratio: Double(f.size) / Double(maxSize), color: .orange, width: 60)
                        Text(fmt(f.size)).font(.callout.monospacedDigit().weight(.medium)).frame(width: 72, alignment: .trailing)
                        RevealButton(url: f.url)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: app.bgImage == nil))
                .scrollContentBackground(app.bgImage == nil ? .automatic : .hidden)
            }

            ActionBar(status: vm.status, busy: vm.busy) {
                if vm.scanned && !vm.files.isEmpty {
                    Button(t("移到废纸篓 %@", "\(fmt(vm.selectedSize))")) { vm.showConfirm = true }
                        .buttonStyle(.borderedProminent).tint(.orange)
                        .disabled(vm.selectedSize == 0 || vm.busy)
                }
            }
        }
        .navigationTitle(t("大文件"))
        .alert(t("将 %@ 个文件移到废纸篓？", "\(vm.selected.count)"), isPresented: $vm.showConfirm) {
            Button(t("取消"), role: .cancel) {}
            Button(t("移到废纸篓"), role: .destructive) { vm.trash(app: app) }
        } message: { Text(t("共 %@。这些是你的个人文件，请确认不再需要。可从废纸篓恢复。", "\(fmt(vm.selectedSize))")) }
    }
}

struct EmptyState: View {
    let icon: String, color: Color, title: String, message: String
    var body: some View {
        VStack(spacing: 12) {
            IconTile(symbol: icon, color: color, size: 64)
            Text(title).font(.title3.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - 应用卸载

struct UninstallView: View {
    @ObservedObject var app: AppState
    @ObservedObject var vm: UninstallModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField(t("搜索应用"), text: $vm.query).textFieldStyle(.roundedBorder).padding(10)
                if vm.loading {
                    ProgressView().frame(maxHeight: .infinity)
                } else {
                    List(vm.visibleApps, selection: Binding(
                        get: { vm.current?.url },
                        set: { url in vm.select(vm.apps.first { $0.url == url }) })) { a in
                        HStack(spacing: 8) {
                            if let icon = vm.icons[a.url] { Image(nsImage: icon).resizable().frame(width: 26, height: 26) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).lineLimit(1)
                                Text(a.size.map(fmt) ?? t("计算中…")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(a.url)
                    }
                }
            }
            .scrollContentBackground(app.bgImage == nil ? .automatic : .hidden)
            .background(app.bgImage == nil ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.regularMaterial))
            .frame(minWidth: 220, idealWidth: 250, maxWidth: 320)

            detail.frame(minWidth: 380, maxWidth: .infinity)
        }
        .navigationTitle(t("应用卸载"))
        .onAppear { vm.load() }
        .alert(t("卸载 %@？", "\(vm.current?.name ?? "")"), isPresented: $vm.showConfirm) {
            Button(t("取消"), role: .cancel) {}
            Button(t("卸载"), role: .destructive) { vm.uninstall(app: app) }
        } message: { Text(t("应用及所选的 %@ 项相关文件（共 %@）将移到废纸篓，可以恢复。", "\(vm.selected.count)", "\(fmt(vm.selectedSize))")) }
    }

    @ViewBuilder private var detail: some View {
        VStack(spacing: 0) {
            if let a = vm.current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            if let icon = vm.icons[a.url] { Image(nsImage: icon).resizable().frame(width: 64, height: 64) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.name).font(.title2.bold())
                                Text("\(a.bundleID)  ·  v\(a.version)").font(.caption).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                if vm.isRunning { Tag(text: t("正在运行"), color: .orange) }
                            }
                        }
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                fileRow(FoundItem(url: a.url, size: a.size ?? 0), label: t("应用本体"))
                                if !vm.leftovers.isEmpty { Divider() }
                                ForEach(vm.leftovers) { item in
                                    fileRow(item, label: item.url.deletingLastPathComponent().lastPathComponent)
                                }
                                if vm.leftovers.isEmpty {
                                    Text(t("没有找到残留文件")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                EmptyState(icon: "trash.square", color: .pink, title: t("彻底卸载应用"),
                           message: t("选择左侧的应用，MacSweep 会找出它在资料库中的\n缓存、偏好设置、容器等残留文件，一并移到废纸篓。"))
            }
            ActionBar(status: vm.status, busy: vm.busy) {
                if vm.current != nil {
                    if vm.isRunning {
                        Button(t("退出应用")) { vm.quitApp() }
                    }
                    Button(t("卸载 %@", "\(fmt(vm.selectedSize))")) { vm.showConfirm = true }
                        .buttonStyle(.borderedProminent).tint(.pink)
                        .disabled(vm.selected.isEmpty || vm.busy || vm.isRunning)
                }
            }
        }
    }

    private func fileRow(_ item: FoundItem, label: String) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: vm.binding(item.url)).labelsHidden().toggleStyle(.checkbox)
            Tag(text: label, color: .secondary)
            Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle).help(item.url.path)
            Spacer()
            Text(fmt(item.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            RevealButton(url: item.url)
        }
    }
}
