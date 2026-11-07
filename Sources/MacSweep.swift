// MacSweep — 一个轻量的 macOS 清理小工具（单文件 SwiftUI）
//
// 设计参考：
//   • tw93/Mole               — 按类别深度清理缓存/日志/开发者垃圾，先预览后清理
//   • alienator88/Pearcleaner — 安全优先、移到废纸篓可恢复
//   • mac-cleanup/mac-cleanup-py — 规则化的清理模块 + dry-run
//
// 安全原则：
//   1. 只扫描白名单路径，只清理其子项，绝不删除白名单目录本身
//   2. 先扫描预览，用户勾选后才清理
//   3. 默认“移到废纸篓”（可恢复）；只有“清空废纸篓”是永久删除，且需要二次确认
//   4. 不跟随符号链接；正在运行的应用的缓存默认不勾选

import SwiftUI
import AppKit

let appVersion = "1.1.0"

// MARK: - 清理规则

enum ScanMode {
    case children                                            // 清理目录下的所有子项
    case files(olderThanDays: Int, extensions: Set<String>)  // 只清理指定扩展名（且超过 N 天）的文件
}

struct Rule: Identifiable {
    let id: String
    let name: String
    let detail: String
    let icon: String
    /// 根目录。支持 `~` 与单段通配符 `*`，例如 "~/Library/Application Support/*/GPUCache"
    let roots: [String]
    let mode: ScanMode
    let defaultOn: Bool
    var permanent: Bool = false                               // true = 永久删除（仅废纸篓）
}

let allRules: [Rule] = [
    Rule(id: "caches", name: "用户缓存", detail: "~/Library/Caches，应用会自动重建",
         icon: "archivebox", roots: ["~/Library/Caches"], mode: .children, defaultOn: true),
    Rule(id: "logs", name: "日志文件", detail: "~/Library/Logs 中的应用日志与诊断报告",
         icon: "doc.text", roots: ["~/Library/Logs"], mode: .children, defaultOn: true),
    Rule(id: "appcache", name: "应用内缓存", detail: "Electron / Chromium 应用（VS Code、Slack、Discord 等）的 Cache、GPUCache",
         icon: "app.dashed",
         roots: ["~/Library/Application Support/*/Cache",
                 "~/Library/Application Support/*/Code Cache",
                 "~/Library/Application Support/*/GPUCache",
                 "~/Library/Application Support/*/CachedData",
                 "~/Library/Application Support/*/Service Worker/CacheStorage"],
         mode: .children, defaultOn: true),
    Rule(id: "xcode", name: "Xcode 构建产物", detail: "DerivedData、模拟器缓存、设备支持文件",
         icon: "hammer", roots: ["~/Library/Developer/Xcode/DerivedData",
                                 "~/Library/Developer/CoreSimulator/Caches",
                                 "~/Library/Developer/Xcode/iOS DeviceSupport",
                                 "~/Library/Developer/Xcode/watchOS DeviceSupport"],
         mode: .children, defaultOn: true),
    Rule(id: "devcache", name: "开发工具缓存", detail: "npm、yarn、pnpm、Gradle、CocoaPods、Cargo 下载缓存",
         icon: "shippingbox", roots: ["~/.npm/_cacache", "~/.yarn/cache", "~/Library/pnpm/store",
                                      "~/.gradle/caches", "~/.cocoapods/repos",
                                      "~/.cargo/registry/cache"],
         mode: .children, defaultOn: true),
    Rule(id: "conda", name: "Conda 安装包缓存", detail: "anaconda / miniconda 已下载的安装包（等同 conda clean -p）",
         icon: "cube.box", roots: ["/opt/anaconda3/pkgs", "/opt/miniconda3/pkgs", "~/anaconda3/pkgs",
                                   "~/miniconda3/pkgs", "~/opt/anaconda3/pkgs"],
         mode: .files(olderThanDays: 0, extensions: ["conda", "bz2"]), defaultOn: false),
    Rule(id: "installers", name: "旧安装包", detail: "下载文件夹中 30 天前的 .dmg / .pkg / .iso",
         icon: "arrow.down.circle", roots: ["~/Downloads"],
         mode: .files(olderThanDays: 30, extensions: ["dmg", "pkg", "iso"]), defaultOn: false),
    Rule(id: "trash", name: "废纸篓", detail: "永久删除，无法恢复（需要“完全磁盘访问权限”）",
         icon: "trash", roots: ["~/.Trash"], mode: .children, defaultOn: false, permanent: true),
]

// MARK: - 扫描结果

struct FoundItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let inUse: Bool          // 属于正在运行的应用
}

struct CategoryResult: Identifiable {
    var id: String { rule.id }
    let rule: Rule
    let items: [FoundItem]
    let total: Int64

    init(rule: Rule, items: [FoundItem]) {
        self.rule = rule
        self.items = items.sorted { $0.size > $1.size }
        self.total = items.reduce(0) { $0 + $1.size }
    }
}

// MARK: - 扫描/清理引擎（与 UI 无关，GUI 和 CLI 共用）

enum Engine {
    static let fm = FileManager.default
    static let sizeKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                             .isSymbolicLinkKey, .isDirectoryKey]
    static let ignoredNames: Set<String> = [".DS_Store", ".localized", ".com.apple.timemachine.supported"]

    /// 展开 `~` 和单段 `*` 通配符，返回存在的目录
    static func resolve(_ pattern: String) -> [URL] {
        let path = (pattern as NSString).expandingTildeInPath
        var bases = [URL(fileURLWithPath: "/")]
        for part in path.split(separator: "/").map(String.init) {
            if part == "*" {
                bases = bases.flatMap { base in
                    ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [])
                        .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
                }
            } else {
                bases = bases.map { $0.appendingPathComponent(part) }
            }
        }
        return bases.filter { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// 计算一个文件或目录占用的磁盘空间（不跟随符号链接）
    static func allocatedSize(of url: URL) -> Int64 {
        let keySet = Set(sizeKeys)
        guard let v = try? url.resourceValues(forKeys: keySet), v.isSymbolicLink != true else { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: sizeKeys,
                                 options: [], errorHandler: { _, _ in true }) {
            for case let f as URL in e {
                if let r = try? f.resourceValues(forKeys: keySet), r.isSymbolicLink != true {
                    total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
                }
            }
        }
        return total
    }

    /// 正在运行的应用的 bundle id 和名称（小写），用于保护其缓存
    static func runningAppKeys() -> Set<String> {
        var keys = Set<String>()
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let b = app.bundleIdentifier?.lowercased() { keys.insert(b) }
            if let n = app.localizedName?.lowercased() { keys.insert(n) }
        }
        keys.subtract(["macsweep", "io.github.macsweep", "finder", "com.apple.finder"])
        return keys
    }

    static func isInUse(_ url: URL, running: Set<String>) -> Bool {
        // 检查路径最后几段（如 Caches/com.google.Chrome、Application Support/Slack/Cache/xxx）
        url.pathComponents.suffix(3).contains { running.contains($0.lowercased()) }
    }

    static func candidates(for rule: Rule) -> [URL] {
        var cutoff: Date?
        if case let .files(days, _) = rule.mode, days > 0 {
            cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        }
        var out: [URL] = []
        for root in rule.roots {
            for dir in resolve(root) {
                guard let children = try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
                for child in children where !ignoredNames.contains(child.lastPathComponent) {
                    if case let .files(_, exts) = rule.mode {
                        guard exts.contains(child.pathExtension.lowercased()) else { continue }
                        if let cutoff {
                            let mod = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?
                                .contentModificationDate ?? .distantFuture
                            guard mod < cutoff else { continue }
                        }
                    }
                    out.append(child)
                }
            }
        }
        return out
    }

    /// 扫描一条规则；子项大小并行计算
    static func scan(_ rule: Rule, running: Set<String>) -> CategoryResult {
        let urls = candidates(for: rule)
        var sizes = [Int64](repeating: 0, count: urls.count)
        sizes.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                buf[i] = allocatedSize(of: urls[i])
            }
        }
        let items = zip(urls, sizes).compactMap { url, size in
            size > 0 ? FoundItem(url: url, size: size, inUse: isInUse(url, running: running)) : nil
        }
        return CategoryResult(rule: rule, items: items)
    }

    /// 返回 (成功释放的字节数, 失败的条目数)
    static func clean(_ items: [FoundItem], permanent: Bool) -> (freed: Int64, failed: Int) {
        var freed: Int64 = 0, failed = 0
        for item in items {
            do {
                if permanent { try fm.removeItem(at: item.url) }
                else { try fm.trashItem(at: item.url, resultingItemURL: nil) }
                freed += item.size
            } catch { failed += 1 }
        }
        return (freed, failed)
    }

    static func diskInfo() -> (free: Int64, total: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return (v?.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v?.volumeTotalCapacity ?? 0))
    }
}

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

// MARK: - ViewModel

@MainActor
final class Sweeper: ObservableObject {
    @Published var results: [CategoryResult] = []
    @Published var selected: Set<URL> = []
    @Published var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled), forKey: "enabledRules") }
    }
    @Published var scanning = false
    @Published var cleaning = false
    @Published var showConfirm = false
    @Published var progress = 0.0
    @Published var status = "点击“扫描”开始，扫描不会删除任何文件。"
    @Published var disk = Engine.diskInfo()
    @Published private(set) var selectedSize: Int64 = 0

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "enabledRules")
        enabled = Set(saved ?? allRules.filter(\.defaultOn).map(\.id))
    }

    var selectedIncludesPermanent: Bool {
        results.contains { $0.rule.permanent && $0.items.contains { selected.contains($0.url) } }
    }

    private func recomputeSelectedSize() {
        selectedSize = results.lazy.flatMap(\.items).filter { self.selected.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    func setSelected(_ url: URL, _ on: Bool) {
        if on { selected.insert(url) } else { selected.remove(url) }
        recomputeSelectedSize()
    }

    func toggleCategory(_ r: CategoryResult, on: Bool) {
        for i in r.items { if on { selected.insert(i.url) } else { selected.remove(i.url) } }
        recomputeSelectedSize()
    }

    func reset() {
        results = []; selected = []; selectedSize = 0
    }

    func scan() {
        scanning = true
        progress = 0
        status = "正在扫描…"
        let rules = allRules.filter { enabled.contains($0.id) }
        let running = Engine.runningAppKeys()
        Task {
            var res: [CategoryResult] = []
            await withTaskGroup(of: CategoryResult.self) { group in
                for rule in rules {
                    group.addTask(priority: .userInitiated) { Engine.scan(rule, running: running) }
                }
                for await r in group {
                    res.append(r)
                    progress = Double(res.count) / Double(max(rules.count, 1))
                    status = "已扫描 \(res.count)/\(rules.count)：\(r.rule.name)"
                }
            }
            // 保持规则定义的顺序
            let order = Dictionary(uniqueKeysWithValues: allRules.enumerated().map { ($1.id, $0) })
            results = res.filter { !$0.items.isEmpty }.sorted { order[$0.id]! < order[$1.id]! }
            selected = Set(results.flatMap(\.items).filter { !$0.inUse }.map(\.url))
            recomputeSelectedSize()
            scanning = false
            let total = results.reduce(0) { $0 + $1.total }
            let inUse = results.flatMap(\.items).filter(\.inUse).count
            status = results.isEmpty ? "很干净，没有找到可清理的内容。"
                : "共找到 \(fmt(total)) 可清理" + (inUse > 0 ? "，\(inUse) 项属于运行中的应用，默认未勾选。" : "。")
        }
    }

    func clean() {
        cleaning = true
        status = "正在清理…"
        let groups = results.map { r in (r.rule.permanent, r.items.filter { selected.contains($0.url) }) }
        Task {
            let (freed, failed) = await Task.detached(priority: .userInitiated) { () -> (Int64, Int) in
                var freed: Int64 = 0, failed = 0
                for (permanent, items) in groups where !items.isEmpty {
                    let r = Engine.clean(items, permanent: permanent)
                    freed += r.freed; failed += r.failed
                }
                return (freed, failed)
            }.value
            cleaning = false
            disk = Engine.diskInfo()
            status = "已清理 \(fmt(freed))，移到废纸篓的项目可恢复"
                + (failed > 0 ? "；\(failed) 项被系统保护或正在使用，已跳过。" : "。")
            reset()
        }
    }
}

// MARK: - UI

struct ContentView: View {
    @StateObject private var vm = Sweeper()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if vm.results.isEmpty { rulePicker } else { resultList }
            Divider()
            footer
        }
        .frame(minWidth: 580, minHeight: 540)
        .alert("确认清理 \(fmt(vm.selectedSize))？", isPresented: $vm.showConfirm) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) { vm.clean() }
        } message: {
            Text(vm.selectedIncludesPermanent
                 ? "废纸篓中的内容将被永久删除，无法恢复。其余项目会移到废纸篓。"
                 : "所选项目将移到废纸篓，需要时可以恢复。建议先退出相关应用。")
        }
    }

    private var header: some View {
        let used = vm.disk.total - vm.disk.free
        let ratio = Double(used) / Double(max(vm.disk.total, 1))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
                Text("MacSweep").font(.title2.bold())
                Spacer()
                Text("可用 \(fmt(vm.disk.free)) / \(fmt(vm.disk.total))")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: ratio).tint(ratio > 0.9 ? .red : ratio > 0.75 ? .orange : .accentColor)
        }
        .padding()
    }

    private var rulePicker: some View {
        List {
            Section("选择要扫描的类别") {
                ForEach(allRules) { rule in
                    Toggle(isOn: Binding(
                        get: { vm.enabled.contains(rule.id) },
                        set: { on in if on { vm.enabled.insert(rule.id) } else { vm.enabled.remove(rule.id) } })) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rule.name)
                                Text(rule.detail).font(.caption)
                                    .foregroundStyle(rule.permanent ? .red : .secondary)
                            }
                        } icon: { Image(systemName: rule.icon) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var resultList: some View {
        List {
            ForEach(vm.results) { r in
                let selCount = r.items.lazy.filter { vm.selected.contains($0.url) }.count
                DisclosureGroup {
                    ForEach(r.items.prefix(200)) { item in itemRow(item) }
                    if r.items.count > 200 {
                        Text("另有 \(r.items.count - 200) 个较小项目").font(.caption).foregroundStyle(.secondary)
                    }
                } label: {
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { selCount == r.items.count },
                            set: { vm.toggleCategory(r, on: $0) })).labelsHidden()
                        Image(systemName: r.rule.icon).frame(width: 20)
                        Text(r.rule.name).bold()
                        if r.rule.permanent { tag("永久删除", .red) }
                        Spacer()
                        Text("\(selCount)/\(r.items.count) 项 · \(fmt(r.total))")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }

    private func itemRow(_ item: FoundItem) -> some View {
        Toggle(isOn: Binding(get: { vm.selected.contains(item.url) },
                             set: { vm.setSelected(item.url, $0) })) {
            HStack {
                Text(displayName(item.url)).lineLimit(1).truncationMode(.middle).help(item.url.path)
                if item.inUse { tag("运行中", .orange) }
                Spacer()
                Text(fmt(item.size)).foregroundStyle(.secondary).monospacedDigit()
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: {
                    Image(systemName: "magnifyingglass")
                }.buttonStyle(.borderless).help("在访达中显示")
            }
        }
    }

    /// 通配符规则下（如 Application Support/Slack/Cache/xxx）显示“Slack › xxx”更易读
    private func displayName(_ url: URL) -> String {
        let c = url.pathComponents
        if let i = c.firstIndex(of: "Application Support"), i + 1 < c.count - 1 {
            return "\(c[i + 1]) › \(url.lastPathComponent)"
        }
        return url.lastPathComponent
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
            .foregroundStyle(color).background(color.opacity(0.12), in: Capsule())
    }

    private var footer: some View {
        HStack {
            if vm.scanning {
                ProgressView(value: vm.progress).frame(width: 80)
            } else if vm.cleaning {
                ProgressView().controlSize(.small)
            }
            Text(vm.status).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            if !vm.results.isEmpty {
                Button("返回") { vm.reset() }.disabled(vm.cleaning)
                Button("清理 \(fmt(vm.selectedSize))") { vm.showConfirm = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.selectedSize == 0 || vm.cleaning)
            } else {
                Button("扫描") { vm.scan() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.scanning || vm.enabled.isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - 命令行模式（只读）

enum CLI {
    /// 中文按 2 个字符宽度计算，保证终端对齐
    static func pad(_ s: String, _ width: Int) -> String {
        let w = s.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? 2 : 1) }
        return s + String(repeating: " ", count: max(1, width - w))
    }

    static func run(_ args: [String]) -> Never {
        if args.contains("--help") || args.contains("-h") {
            print("""
            MacSweep \(appVersion) — 轻量 macOS 清理工具

            用法：
              MacSweep             打开图形界面
              MacSweep --scan      命令行预览可清理内容（只读，不删除）
              MacSweep --json      以 JSON 输出扫描结果（只读）
              MacSweep --version   显示版本
            """)
            exit(0)
        }
        if args.contains("--version") { print(appVersion); exit(0) }

        let running = Engine.runningAppKeys()
        let results = allRules.map { Engine.scan($0, running: running) }
        if args.contains("--json") {
            let json = results.map { r -> [String: Any] in
                ["id": r.rule.id, "name": r.rule.name, "bytes": r.total,
                 "items": r.items.map { ["path": $0.url.path, "bytes": $0.size, "inUse": $0.inUse] }]
            }
            let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            exit(0)
        }
        for r in results {
            print(pad(r.rule.name, 18) + pad(fmt(r.total), 11) + "\(r.items.count) 项")
            for i in r.items.prefix(3) {
                print("    " + pad(fmt(i.size), 11) + i.url.path + (i.inUse ? "  [运行中]" : ""))
            }
        }
        print("合计可清理：\(fmt(results.reduce(0) { $0 + $1.total }))（只读预览，未删除任何文件）")
        exit(0)
    }
}

// MARK: - 入口

@main
struct MacSweepApp: App {
    init() {
        let args = Array(CommandLine.arguments.dropFirst())
        // 系统启动时可能带 -NSxxx / -Apple 参数，忽略它们
        if args.contains(where: { $0.hasPrefix("-") && !$0.hasPrefix("-NS") && !$0.hasPrefix("-Apple") }) {
            CLI.run(args)
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("MacSweep") { ContentView() }
            .windowResizability(.contentMinSize)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
