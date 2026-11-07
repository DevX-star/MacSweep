// Engine.swift — 清理规则与扫描/清理引擎（与 UI 无关，GUI 和 CLI 共用）
//
// 安全原则：
//   1. 只扫描白名单路径，只清理其子项，绝不删除白名单目录本身
//   2. 先扫描预览，用户勾选后才清理
//   3. 默认“移到废纸篓”（可恢复）；只有“清空废纸篓”是永久删除，且需要二次确认
//   4. 不跟随符号链接；正在运行的应用的缓存默认不勾选

import SwiftUI
import AppKit

let appVersion = "1.3.2"

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
    let color: Color
    /// 根目录。支持 `~` 与单段通配符 `*`，例如 "~/Library/Application Support/*/GPUCache"
    let roots: [String]
    let mode: ScanMode
    let defaultOn: Bool
    var permanent: Bool = false                               // true = 永久删除（仅废纸篓）

    /// 本地化后的名称与描述（name/detail 本身是中文键）
    var title: String { t(name) }
    var desc: String { t(detail) }
}

let allRules: [Rule] = [
    Rule(id: "caches", name: "用户缓存", detail: "~/Library/Caches，应用会自动重建",
         icon: "archivebox.fill", color: .blue, roots: ["~/Library/Caches"], mode: .children, defaultOn: true),
    Rule(id: "logs", name: "日志文件", detail: "应用日志与诊断报告",
         icon: "doc.text.fill", color: .gray, roots: ["~/Library/Logs"], mode: .children, defaultOn: true),
    Rule(id: "appcache", name: "应用内缓存", detail: "VS Code、Slack、Discord 等 Electron 应用缓存",
         icon: "square.stack.3d.up.fill", color: .purple,
         roots: ["~/Library/Application Support/*/Cache",
                 "~/Library/Application Support/*/Code Cache",
                 "~/Library/Application Support/*/GPUCache",
                 "~/Library/Application Support/*/CachedData",
                 "~/Library/Application Support/*/Service Worker/CacheStorage"],
         mode: .children, defaultOn: true),
    Rule(id: "xcode", name: "Xcode 构建产物", detail: "DerivedData、模拟器缓存、设备支持文件",
         icon: "hammer.fill", color: .cyan,
         roots: ["~/Library/Developer/Xcode/DerivedData",
                 "~/Library/Developer/CoreSimulator/Caches",
                 "~/Library/Developer/Xcode/iOS DeviceSupport",
                 "~/Library/Developer/Xcode/watchOS DeviceSupport"],
         mode: .children, defaultOn: true),
    Rule(id: "devcache", name: "开发工具缓存", detail: "npm、yarn、pnpm、Gradle、CocoaPods、Cargo",
         icon: "shippingbox.fill", color: .orange,
         roots: ["~/.npm/_cacache", "~/.yarn/cache", "~/Library/pnpm/store",
                 "~/.gradle/caches", "~/.cocoapods/repos", "~/.cargo/registry/cache"],
         mode: .children, defaultOn: true),
    Rule(id: "conda", name: "Conda 安装包", detail: "已下载的 conda 安装包（等同 conda clean -p）",
         icon: "cube.fill", color: .green,
         roots: ["/opt/anaconda3/pkgs", "/opt/miniconda3/pkgs", "~/anaconda3/pkgs",
                 "~/miniconda3/pkgs", "~/opt/anaconda3/pkgs"],
         mode: .files(olderThanDays: 0, extensions: ["conda", "bz2"]), defaultOn: false),
    Rule(id: "installers", name: "旧安装包", detail: "下载文件夹中 30 天前的 .dmg / .pkg / .iso",
         icon: "arrow.down.circle.fill", color: .teal, roots: ["~/Downloads"],
         mode: .files(olderThanDays: 30, extensions: ["dmg", "pkg", "iso"]), defaultOn: false),
    Rule(id: "trash", name: "废纸篓", detail: "永久删除，无法恢复（需完全磁盘访问权限）",
         icon: "trash.fill", color: .red, roots: ["~/.Trash"], mode: .children, defaultOn: false, permanent: true),
]

// MARK: - 数据结构

struct FoundItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var inUse: Bool = false          // 属于正在运行的应用
    var modified: Date? = nil
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

struct AppInfo: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    var size: Int64? = nil
    static func == (a: AppInfo, b: AppInfo) -> Bool { a.url == b.url && a.size == b.size }
    func hash(into h: inout Hasher) { h.combine(url) }
}

// MARK: - 引擎

enum Engine {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser
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
        return bases.filter(isDirectory)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
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

    /// 并行计算多个路径的大小
    static func sizes(of urls: [URL]) -> [Int64] {
        var out = [Int64](repeating: 0, count: urls.count)
        out.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in buf[i] = allocatedSize(of: urls[i]) }
        }
        return out
    }

    // MARK: 智能清理

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

    static func scan(_ rule: Rule, running: Set<String>) -> CategoryResult {
        let urls = candidates(for: rule)
        let items = zip(urls, sizes(of: urls)).compactMap { url, size in
            size > 0 ? FoundItem(url: url, size: size, inUse: isInUse(url, running: running)) : nil
        }
        return CategoryResult(rule: rule, items: items)
    }

    // MARK: 大文件

    /// 在用户主目录中查找大文件（跳过 ~/Library、隐藏文件和应用包内部）
    static func largeFiles(minBytes: Int64, limit: Int = 500) -> [FoundItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
                                      .contentModificationDateKey, .isSymbolicLinkKey]
        let tops = ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.lastPathComponent != "Library" }
        let lock = NSLock()
        var found: [FoundItem] = []
        DispatchQueue.concurrentPerform(iterations: tops.count) { i in
            var local: [FoundItem] = []
            func consider(_ f: URL) {
                guard let r = try? f.resourceValues(forKeys: Set(keys)), r.isRegularFile == true,
                      r.isSymbolicLink != true else { return }
                let size = Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
                if size >= minBytes { local.append(FoundItem(url: f, size: size, modified: r.contentModificationDate)) }
            }
            let top = tops[i]
            if isDirectory(top) {
                if let e = fm.enumerator(at: top, includingPropertiesForKeys: keys,
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                         errorHandler: { _, _ in true }) {
                    for case let f as URL in e { consider(f) }
                }
            } else { consider(top) }
            lock.lock(); found += local; lock.unlock()
        }
        return Array(found.sorted { $0.size > $1.size }.prefix(limit))
    }

    // MARK: 应用卸载

    static func installedApps() -> [AppInfo] {
        let dirs = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var apps: [AppInfo] = []
        for dir in dirs {
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where url.pathExtension == "app" {
                guard let b = Bundle(url: url), let bid = b.bundleIdentifier,
                      !bid.hasPrefix("com.apple.") else { continue }
                let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let ver = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                apps.append(AppInfo(url: url, name: name, bundleID: bid, version: ver))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 查找应用的残留文件：按 bundle id（带分隔边界）精确匹配，名称只在少数目录中完全相等才匹配
    static func leftovers(for app: AppInfo) -> [FoundItem] {
        let lib = home.appendingPathComponent("Library")
        let bid = app.bundleID.lowercased()
        let appName = app.url.deletingPathExtension().lastPathComponent.lowercased()
        let byID = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers",
                    "Saved Application State", "Logs", "HTTPStorages", "WebKit", "Cookies",
                    "LaunchAgents", "Application Scripts", "Preferences/ByHost"]
        let byName: Set<String> = ["Application Support", "Caches", "Logs"]

        func matches(_ raw: String, dir: String) -> Bool {
            let n = raw.lowercased()
            if n == bid || n.hasPrefix(bid + ".") || n.hasSuffix("." + bid) || n.contains("." + bid + ".") {
                return true
            }
            return byName.contains(dir) && appName.count >= 3 && n == appName
        }

        var urls: [URL] = []
        for dir in byID {
            let base = lib.appendingPathComponent(dir)
            for child in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            where matches(child.lastPathComponent, dir: dir) {
                urls.append(child)
            }
        }
        return zip(urls, sizes(of: urls)).map { FoundItem(url: $0, size: $1) }.sorted { $0.size > $1.size }
    }

    // MARK: 清理

    /// 返回 (成功释放的字节数, 失败的条目数)
    static func remove(_ items: [FoundItem], permanent: Bool = false) -> (freed: Int64, failed: Int) {
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
