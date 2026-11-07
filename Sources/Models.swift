// Models.swift — 各页面的状态（ObservableObject）

import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum Pane: String, CaseIterable, Identifiable {
    case clean, large, uninstall
    var id: String { rawValue }
    var title: String { ["clean": "智能清理", "large": "大文件", "uninstall": "应用卸载"][rawValue]! }
    var icon: String { ["clean": "sparkles", "large": "doc.viewfinder", "uninstall": "trash.square"][rawValue]! }
    var color: Color { ["clean": Color.blue, "large": .orange, "uninstall": .pink][rawValue]! }
}

/// 全局状态：当前页面、磁盘信息、累计释放空间
@MainActor
final class AppState: ObservableObject {
    @Published var pane: Pane? = .clean
    @Published var disk = Engine.diskInfo()
    @Published var totalFreed: Int64 = Int64(UserDefaults.standard.integer(forKey: "totalFreed"))
    @Published var lastFreed: Int64? = nil

    var usedRatio: Double {
        Double(disk.total - disk.free) / Double(max(disk.total, 1))
    }

    func record(freed: Int64) {
        totalFreed += freed
        lastFreed = freed
        UserDefaults.standard.set(Int(totalFreed), forKey: "totalFreed")
        disk = Engine.diskInfo()
    }

    // MARK: 背景图（复制到 ~/Library/Application Support/MacSweep/，不依赖原文件）

    @Published var bgImage: NSImage? = nil
    @Published var showAppearance = false
    @Published var bgDim: Double = UserDefaults.standard.object(forKey: "bgDim") as? Double ?? 0.45 {
        didSet { UserDefaults.standard.set(bgDim, forKey: "bgDim") }
    }
    @Published var bgBlur: Double = UserDefaults.standard.object(forKey: "bgBlur") as? Double ?? 0 {
        didSet { UserDefaults.standard.set(bgBlur, forKey: "bgBlur") }
    }

    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacSweep", isDirectory: true)

    init() {
        if let path = UserDefaults.standard.string(forKey: "backgroundPath") {
            bgImage = NSImage(contentsOfFile: path)
        }
    }

    func chooseBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "选择一张图片作为 MacSweep 的背景"
        panel.prompt = "设为背景"
        if panel.runModal() == .OK, let url = panel.url { setBackground(from: url) }
    }

    @discardableResult
    func setBackground(from url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
              let img = NSImage(contentsOf: url), img.isValid else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        // 删除旧背景，文件名带时间戳避免缓存
        for old in (try? fm.contentsOfDirectory(at: Self.supportDir, includingPropertiesForKeys: nil)) ?? []
        where old.lastPathComponent.hasPrefix("background") { try? fm.removeItem(at: old) }
        let dest = Self.supportDir.appendingPathComponent("background-\(Int(Date().timeIntervalSince1970)).\(url.pathExtension.lowercased())")
        do { try fm.copyItem(at: url, to: dest) } catch { return false }
        UserDefaults.standard.set(dest.path, forKey: "backgroundPath")
        withAnimation(.easeInOut(duration: 0.3)) { bgImage = img }
        return true
    }

    func clearBackground() {
        if let path = UserDefaults.standard.string(forKey: "backgroundPath") {
            try? FileManager.default.removeItem(atPath: path)
        }
        UserDefaults.standard.removeObject(forKey: "backgroundPath")
        withAnimation(.easeInOut(duration: 0.3)) { bgImage = nil }
    }
}

/// 可勾选结果列表的通用逻辑
@MainActor
class Selectable: ObservableObject {
    @Published var selected: Set<URL> = []
    @Published private(set) var selectedSize: Int64 = 0
    @Published var busy = false
    @Published var showConfirm = false
    @Published var status = ""

    var allItems: [FoundItem] { [] }

    func recompute() {
        selectedSize = allItems.lazy.filter { self.selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }
    func set(_ url: URL, _ on: Bool) {
        if on { selected.insert(url) } else { selected.remove(url) }
        recompute()
    }
    func setAll(_ items: [FoundItem], _ on: Bool) {
        for i in items { if on { selected.insert(i.url) } else { selected.remove(i.url) } }
        recompute()
    }
    func binding(_ url: URL) -> Binding<Bool> {
        Binding(get: { self.selected.contains(url) }, set: { self.set(url, $0) })
    }

    /// 后台移到废纸篓（或永久删除），返回 (释放字节, 失败数)
    func removeInBackground(_ groups: [(permanent: Bool, items: [FoundItem])]) async -> (Int64, Int) {
        await Task.detached(priority: .userInitiated) { () -> (Int64, Int) in
            var freed: Int64 = 0, failed = 0
            for g in groups where !g.items.isEmpty {
                let r = Engine.remove(g.items, permanent: g.permanent)
                freed += r.freed; failed += r.failed
            }
            return (freed, failed)
        }.value
    }
}

// MARK: - 智能清理

@MainActor
final class SweepModel: Selectable {
    @Published var results: [CategoryResult] = []
    @Published var progress = 0.0
    @Published var enabled: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabled), forKey: "enabledRules") }
    }

    override init() {
        let saved = UserDefaults.standard.stringArray(forKey: "enabledRules")
        enabled = Set(saved ?? allRules.filter(\.defaultOn).map(\.id))
        super.init()
        status = "扫描是只读的，不会删除任何文件。"
    }

    override var allItems: [FoundItem] { results.flatMap(\.items) }
    var scanned: Bool { !results.isEmpty }
    var total: Int64 { results.reduce(0) { $0 + $1.total } }
    var maxCategory: Int64 { results.map(\.total).max() ?? 1 }
    var includesPermanent: Bool {
        results.contains { $0.rule.permanent && $0.items.contains { selected.contains($0.url) } }
    }

    func toggleRule(_ id: String) {
        if enabled.contains(id) { enabled.remove(id) } else { enabled.insert(id) }
    }

    func reset() { results = []; selected = []; recompute(); status = "扫描是只读的，不会删除任何文件。" }

    func scan() {
        busy = true; progress = 0; status = "正在扫描…"
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
                    withAnimation { progress = Double(res.count) / Double(max(rules.count, 1)) }
                    status = "已扫描 \(res.count)/\(rules.count)：\(r.rule.name)"
                }
            }
            let order = Dictionary(uniqueKeysWithValues: allRules.enumerated().map { ($1.id, $0) })
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                results = res.filter { !$0.items.isEmpty }.sorted { order[$0.id]! < order[$1.id]! }
            }
            selected = Set(allItems.filter { !$0.inUse }.map(\.url))
            recompute()
            busy = false
            let inUse = allItems.filter(\.inUse).count
            status = results.isEmpty ? "很干净，没有找到可清理的内容 ✨"
                : "找到 \(fmt(total))" + (inUse > 0 ? "，\(inUse) 项属于运行中的应用，默认未勾选" : "")
        }
    }

    func clean(app: AppState) {
        busy = true; status = "正在清理…"
        let groups = results.map { r in (permanent: r.rule.permanent, items: r.items.filter { selected.contains($0.url) }) }
        Task {
            let (freed, failed) = await removeInBackground(groups)
            busy = false
            app.record(freed: freed)
            withAnimation { reset() }
            status = "已释放 \(fmt(freed))" + (failed > 0 ? "，\(failed) 项被保护或正在使用，已跳过" : "")
        }
    }
}

// MARK: - 大文件

@MainActor
final class LargeFileModel: Selectable {
    @Published var files: [FoundItem] = []
    @Published var thresholdMB = 500
    @Published var scanned = false
    @Published var query = ""

    override init() { super.init(); status = "在主目录中查找大文件（跳过系统资料库）" }
    override var allItems: [FoundItem] { files }
    var visible: [FoundItem] {
        query.isEmpty ? files : files.filter { $0.url.path.localizedCaseInsensitiveContains(query) }
    }

    func scan() {
        busy = true; status = "正在查找大于 \(thresholdMB) MB 的文件…"
        let min = Int64(thresholdMB) * 1_000_000
        Task {
            let found = await Task.detached(priority: .userInitiated) { Engine.largeFiles(minBytes: min) }.value
            withAnimation { files = found; scanned = true }
            selected = []; recompute(); busy = false
            status = found.isEmpty ? "没有找到大于 \(thresholdMB) MB 的文件"
                : "找到 \(found.count) 个文件，共 \(fmt(found.reduce(0) { $0 + $1.size }))，请手动勾选"
        }
    }

    func trash(app: AppState) {
        busy = true
        let items = files.filter { selected.contains($0.url) }
        Task {
            let (freed, failed) = await removeInBackground([(false, items)])
            app.record(freed: freed)
            withAnimation { files.removeAll { !FileManager.default.fileExists(atPath: $0.url.path) } }
            selected = []; recompute(); busy = false
            status = "已移到废纸篓 \(fmt(freed))" + (failed > 0 ? "，\(failed) 项失败" : "")
        }
    }
}

// MARK: - 应用卸载

@MainActor
final class UninstallModel: Selectable {
    @Published var apps: [AppInfo] = []
    @Published var icons: [URL: NSImage] = [:]
    @Published var current: AppInfo? = nil
    @Published var leftovers: [FoundItem] = []
    @Published var query = ""
    @Published var loading = false

    override init() { super.init(); status = "选择一个应用，查看它和它的残留文件" }

    override var allItems: [FoundItem] {
        guard let a = current else { return leftovers }
        return [FoundItem(url: a.url, size: a.size ?? 0)] + leftovers
    }
    var visibleApps: [AppInfo] {
        query.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }
    var isRunning: Bool {
        guard let a = current else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleID).isEmpty
    }

    func load() {
        guard apps.isEmpty, !loading else { return }
        loading = true
        Task {
            let list = await Task.detached { Engine.installedApps() }.value
            apps = list
            for a in list { icons[a.url] = NSWorkspace.shared.icon(forFile: a.url.path) }
            loading = false
            // 后台计算应用大小
            let urls = list.map(\.url)
            let sizes = await Task.detached(priority: .utility) { Engine.sizes(of: urls) }.value
            apps = zip(list, sizes).map { var a = $0; a.size = $1; return a }
            if let c = current, let updated = apps.first(where: { $0.url == c.url }) { current = updated; recompute() }
        }
    }

    func select(_ app: AppInfo?) {
        current = app
        leftovers = []
        selected = []
        recompute()
        guard let app else { return }
        Task {
            let found = await Task.detached { Engine.leftovers(for: app) }.value
            guard current?.url == app.url else { return }
            withAnimation { leftovers = found }
            selected = Set(allItems.map(\.url))
            recompute()
            status = "\(app.name)：找到 \(found.count) 个相关文件"
        }
    }

    func quitApp() {
        guard let a = current else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleID).forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.objectWillChange.send() }
    }

    func uninstall(app: AppState) {
        guard let a = current else { return }
        busy = true
        let items = allItems.filter { selected.contains($0.url) }
        Task {
            let (freed, failed) = await removeInBackground([(false, items)])
            app.record(freed: freed)
            busy = false
            if !FileManager.default.fileExists(atPath: a.url.path) {
                withAnimation { apps.removeAll { $0.url == a.url } }
                select(nil)
                status = "已卸载 \(a.name)，释放 \(fmt(freed))" + (failed > 0 ? "，\(failed) 项失败" : "")
            } else {
                select(a)
                status = "无法移除 \(a.name)：可能需要管理员权限，请在访达中手动删除应用本体"
            }
        }
    }
}
