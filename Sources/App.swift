// App.swift — 入口与命令行模式
//
// 设计参考：
//   • tw93/Mole               — 按类别深度清理缓存/日志/开发者垃圾，先预览后清理
//   • alienator88/Pearcleaner — 应用卸载 + 残留文件查找，安全优先
//   • mac-cleanup/mac-cleanup-py — 规则化的清理模块 + dry-run

import SwiftUI
import AppKit

enum CLI {
    /// 中文按 2 个字符宽度计算，保证终端对齐
    static func pad(_ s: String, _ width: Int) -> String {
        let w = s.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E80 ? 2 : 1) }
        return s + String(repeating: " ", count: max(1, width - w))
    }

    static func printJSON(_ obj: Any) {
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    static func run(_ args: [String]) -> Never {
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if args.contains("--help") || args.contains("-h") {
            print("""
            MacSweep \(appVersion) — 轻量 macOS 清理工具（命令行模式均为只读）

            用法：
              MacSweep                       打开图形界面
              MacSweep --scan [--json]       预览可清理内容
              MacSweep --large [MB] [--json] 列出主目录中的大文件（默认 500 MB）
              MacSweep --leftovers <bundleID|应用名>  列出应用及其残留文件
              MacSweep --version             显示版本
            """)
            exit(0)
        }
        if args.contains("--version") { print(appVersion); exit(0) }
        let json = args.contains("--json")

        if args.contains("--large") {
            let mb = Int64(value(after: "--large") ?? "") ?? 500
            let files = Engine.largeFiles(minBytes: mb * 1_000_000)
            if json { printJSON(files.map { ["path": $0.url.path, "bytes": $0.size] }); exit(0) }
            for f in files.prefix(50) { print(pad(fmt(f.size), 11) + f.url.path) }
            print("共 \(files.count) 个 ≥ \(mb) MB 的文件，合计 \(fmt(files.reduce(0) { $0 + $1.size }))")
            exit(0)
        }

        if let q = value(after: "--leftovers") {
            guard let app = Engine.installedApps().first(where: {
                $0.bundleID.caseInsensitiveCompare(q) == .orderedSame || $0.name.caseInsensitiveCompare(q) == .orderedSame
            }) else { print("未找到应用：\(q)（不支持 Apple 自带应用）"); exit(1) }
            let items = [FoundItem(url: app.url, size: Engine.allocatedSize(of: app.url))] + Engine.leftovers(for: app)
            if json { printJSON(items.map { ["path": $0.url.path, "bytes": $0.size] }); exit(0) }
            print("\(app.name) (\(app.bundleID))")
            for i in items { print("  " + pad(fmt(i.size), 11) + i.url.path) }
            print("合计 \(fmt(items.reduce(0) { $0 + $1.size }))")
            exit(0)
        }

        let running = Engine.runningAppKeys()
        let results = allRules.map { Engine.scan($0, running: running) }
        if json {
            printJSON(results.map { r -> [String: Any] in
                ["id": r.rule.id, "name": r.rule.name, "bytes": r.total,
                 "items": r.items.map { ["path": $0.url.path, "bytes": $0.size, "inUse": $0.inUse] }]
            })
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
        WindowGroup("MacSweep") { RootView() }
            .windowResizability(.contentMinSize)
            .windowToolbarStyle(.unified)
            .commands { CommandGroup(replacing: .newItem) {} }
    }
}
