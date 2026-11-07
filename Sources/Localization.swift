// Localization.swift — 轻量的应用内多语言（中文 / 日本語 / English），可在运行时即时切换
//
// 用法：t("清理 %@", size)。键就是中文原文；中文直接返回键，日文/英文查表，
// 查不到时回退到英文，再回退到中文。占位符 %@ 按顺序替换，也支持 %1$@、%2$@ 指定顺序。

import Foundation

enum Lang: String, CaseIterable, Identifiable {
    case system, zh, ja, en
    var id: String { rawValue }

    /// 选项名称始终用各自语言显示，方便找到自己的语言
    var label: String {
        switch self {
        case .system: return t("跟随系统")
        case .zh: return "中文"
        case .ja: return "日本語"
        case .en: return "English"
        }
    }

    /// “跟随系统”时根据系统首选语言决定
    var resolved: Lang {
        guard self == .system else { return self }
        for code in Locale.preferredLanguages {
            if code.hasPrefix("zh") { return .zh }
            if code.hasPrefix("ja") { return .ja }
            if code.hasPrefix("en") { return .en }
        }
        return .en
    }
}

enum Loc {
    static var current: Lang = (Lang(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system).resolved
}

func t(_ key: String, _ args: String...) -> String {
    var s: String
    switch Loc.current {
    case .ja: s = Strings.ja[key] ?? Strings.en[key] ?? key
    case .en: s = Strings.en[key] ?? key
    default: s = key
    }
    for (i, a) in args.enumerated() {
        let positional = "%\(i + 1)$@"
        if s.contains(positional) { s = s.replacingOccurrences(of: positional, with: a) }
        else if let r = s.range(of: "%@") { s.replaceSubrange(r, with: a) }
    }
    return s
}

// MARK: - 翻译表

enum Strings {
    static let en: [String: String] = [
        // 导航 / 通用
        "工具": "Tools",
        "智能清理": "Smart Clean",
        "大文件": "Large Files",
        "应用卸载": "Uninstaller",
        "设置": "Settings",
        "语言": "Language",
        "跟随系统": "System",
        "取消": "Cancel",
        "返回": "Back",
        "移除": "Remove",
        "在访达中显示": "Show in Finder",
        "运行中": "Running",
        "正在运行": "Running",
        "永久删除": "Permanent",
        "可用 %@": "%@ available",
        "累计释放 %@": "%@ freed in total",

        // 背景
        "背景图": "Background",
        "背景与外观": "Background & Appearance",
        "上传图片…": "Upload Image…",
        "未设置": "None",
        "也可以直接把图片拖进窗口": "You can also drop an image onto the window",
        "遮罩": "Dim",
        "模糊": "Blur",
        "遮罩越高，文字越清晰": "Higher dim makes text easier to read",
        "选择一张图片作为 MacSweep 的背景": "Choose an image for the MacSweep background",
        "设为背景": "Set as Background",

        // 清理规则
        "用户缓存": "User Caches",
        "~/Library/Caches，应用会自动重建": "~/Library/Caches — apps rebuild these automatically",
        "日志文件": "Log Files",
        "应用日志与诊断报告": "App logs and diagnostic reports",
        "应用内缓存": "App Caches",
        "VS Code、Slack、Discord 等 Electron 应用缓存": "Caches of Electron apps like VS Code, Slack, Discord",
        "Xcode 构建产物": "Xcode Build Files",
        "DerivedData、模拟器缓存、设备支持文件": "DerivedData, simulator caches, device support",
        "开发工具缓存": "Developer Caches",
        "npm、yarn、pnpm、Gradle、CocoaPods、Cargo": "npm, yarn, pnpm, Gradle, CocoaPods, Cargo",
        "Conda 安装包": "Conda Packages",
        "已下载的 conda 安装包（等同 conda clean -p）": "Downloaded conda packages (same as conda clean -p)",
        "旧安装包": "Old Installers",
        "下载文件夹中 30 天前的 .dmg / .pkg / .iso": ".dmg / .pkg / .iso in Downloads older than 30 days",
        "废纸篓": "Trash",
        "永久删除，无法恢复（需完全磁盘访问权限）": "Deleted permanently (requires Full Disk Access)",

        // 智能清理
        "已使用": "used",
        "让你的 Mac 保持轻盈": "Keep your Mac light",
        "可用 %@ / 共 %@": "%@ available of %@",
        "开始扫描": "Start Scan",
        "扫描中…": "Scanning…",
        "扫描范围": "Scan Scope",
        "可清理空间 · 已勾选 %@": "can be freed · %@ selected",
        "清理完成": "All Clean",
        "刚刚释放了 %@，移到废纸篓的内容可以恢复": "Just freed %@. Items moved to Trash can be restored.",
        "已选 %@/%@ 项": "%@/%@ selected",
        "另有 %@ 个较小项目": "%@ smaller items not shown",
        "清理": "Clean",
        "清理 %@": "Clean %@",
        "确认清理 %@？": "Clean %@?",
        "废纸篓中的内容将被永久删除，无法恢复；其余项目会移到废纸篓。":
            "Items in the Trash will be permanently deleted. Everything else is moved to the Trash.",
        "所选项目将移到废纸篓，需要时可以恢复。建议先退出相关应用。":
            "Selected items will be moved to the Trash and can be restored. Quitting related apps first is recommended.",
        "扫描是只读的，不会删除任何文件。": "Scanning is read-only and never deletes files.",
        "正在扫描…": "Scanning…",
        "已扫描 %@/%@：%@": "Scanned %@/%@: %@",
        "很干净，没有找到可清理的内容 ✨": "Already clean — nothing to remove ✨",
        "找到 %@": "Found %@",
        "，%@ 项属于运行中的应用，默认未勾选": ", %@ items belong to running apps and are unselected",
        "正在清理…": "Cleaning…",
        "已释放 %@": "Freed %@",
        "，%@ 项被保护或正在使用，已跳过": ", %@ protected or in-use items skipped",

        // 大文件
        "最小": "Minimum",
        "查找": "Find",
        "筛选路径": "Filter by path",
        "找出占空间的大文件": "Find the files taking up space",
        "扫描主目录中的视频、安装包、压缩包等大文件。\n不会自动勾选任何文件，请自行确认后再删除。":
            "Scans your home folder for large videos, installers, archives and more.\nNothing is selected automatically — review before deleting.",
        "没有找到大文件": "No large files found",
        "试试降低大小阈值": "Try a lower size threshold",
        "在主目录中查找大文件（跳过系统资料库）": "Finds large files in your home folder (skips ~/Library)",
        "正在查找大于 %@ MB 的文件…": "Looking for files over %@ MB…",
        "没有找到大于 %@ MB 的文件": "No files over %@ MB",
        "找到 %@ 个文件，共 %@，请手动勾选": "Found %@ files (%@). Select the ones to remove.",
        "移到废纸篓": "Move to Trash",
        "移到废纸篓 %@": "Move to Trash %@",
        "将 %@ 个文件移到废纸篓？": "Move %@ files to the Trash?",
        "共 %@。这些是你的个人文件，请确认不再需要。可从废纸篓恢复。":
            "%@ in total. These are your personal files — make sure you no longer need them. They can be restored from the Trash.",
        "已移到废纸篓 %@": "Moved %@ to the Trash",
        "，%@ 项失败": ", %@ failed",

        // 应用卸载
        "搜索应用": "Search apps",
        "计算中…": "Calculating…",
        "彻底卸载应用": "Uninstall Apps Completely",
        "选择左侧的应用，MacSweep 会找出它在资料库中的\n缓存、偏好设置、容器等残留文件，一并移到废纸篓。":
            "Pick an app on the left. MacSweep finds its caches, preferences,\ncontainers and other leftovers in ~/Library and trashes them together.",
        "选择一个应用，查看它和它的残留文件": "Select an app to see it and its leftover files",
        "应用本体": "App",
        "没有找到残留文件": "No leftover files found",
        "退出应用": "Quit App",
        "卸载": "Uninstall",
        "卸载 %@": "Uninstall %@",
        "卸载 %@？": "Uninstall %@?",
        "应用及所选的 %@ 项相关文件（共 %@）将移到废纸篓，可以恢复。":
            "The app and %@ selected related items (%@) will be moved to the Trash and can be restored.",
        "%@：找到 %@ 个相关文件": "%@: found %@ related items",
        "已卸载 %@，释放 %@": "Uninstalled %@, freed %@",
        "无法移除 %@：可能需要管理员权限，请在访达中手动删除应用本体":
            "Couldn't remove %@ — it may need admin rights. Delete the app in Finder.",

        // 命令行
        "轻量 macOS 清理工具（命令行模式均为只读）": "lightweight macOS cleaner (CLI is read-only)",
        "用法：": "Usage:",
        "打开图形界面": "Open the app",
        "预览可清理内容": "Preview what can be cleaned",
        "列出主目录中的大文件（默认 500 MB）": "List large files in your home folder (default 500 MB)",
        "列出应用及其残留文件": "List an app and its leftover files",
        "显示版本": "Show version",
        "%@ 项": "%@ items",
        "  [运行中]": "  [running]",
        "共 %@ 个 ≥ %@ MB 的文件，合计 %@": "%@ files ≥ %@ MB, %@ in total",
        "未找到应用：%@（不支持 Apple 自带应用）": "App not found: %@ (Apple apps are not supported)",
        "合计 %@": "Total %@",
        "合计可清理：%@（只读预览，未删除任何文件）": "Total cleanable: %@ (read-only preview, nothing deleted)",
    ]

    static let ja: [String: String] = [
        // ナビゲーション / 共通
        "工具": "ツール",
        "智能清理": "スマートクリーン",
        "大文件": "大きなファイル",
        "应用卸载": "アンインストーラ",
        "设置": "設定",
        "语言": "言語",
        "跟随系统": "システム",
        "取消": "キャンセル",
        "返回": "戻る",
        "移除": "削除",
        "在访达中显示": "Finder で表示",
        "运行中": "実行中",
        "正在运行": "実行中",
        "永久删除": "完全削除",
        "可用 %@": "空き %@",
        "累计释放 %@": "累計 %@ 解放",

        // 背景
        "背景图": "背景画像",
        "背景与外观": "背景と外観",
        "上传图片…": "画像をアップロード…",
        "未设置": "未設定",
        "也可以直接把图片拖进窗口": "画像をウインドウにドロップしても設定できます",
        "遮罩": "暗さ",
        "模糊": "ぼかし",
        "遮罩越高，文字越清晰": "暗くするほど文字が読みやすくなります",
        "选择一张图片作为 MacSweep 的背景": "MacSweep の背景にする画像を選択",
        "设为背景": "背景に設定",

        // クリーンアップ規則
        "用户缓存": "ユーザキャッシュ",
        "~/Library/Caches，应用会自动重建": "~/Library/Caches（アプリが自動で再作成します）",
        "日志文件": "ログファイル",
        "应用日志与诊断报告": "アプリのログと診断レポート",
        "应用内缓存": "アプリ内キャッシュ",
        "VS Code、Slack、Discord 等 Electron 应用缓存": "VS Code・Slack・Discord などの Electron アプリのキャッシュ",
        "Xcode 构建产物": "Xcode ビルドファイル",
        "DerivedData、模拟器缓存、设备支持文件": "DerivedData・シミュレータキャッシュ・デバイスサポート",
        "开发工具缓存": "開発ツールのキャッシュ",
        "npm、yarn、pnpm、Gradle、CocoaPods、Cargo": "npm・yarn・pnpm・Gradle・CocoaPods・Cargo",
        "Conda 安装包": "Conda パッケージ",
        "已下载的 conda 安装包（等同 conda clean -p）": "ダウンロード済みの conda パッケージ（conda clean -p と同等）",
        "旧安装包": "古いインストーラ",
        "下载文件夹中 30 天前的 .dmg / .pkg / .iso": "ダウンロード内の 30 日以上前の .dmg / .pkg / .iso",
        "废纸篓": "ゴミ箱",
        "永久删除，无法恢复（需完全磁盘访问权限）": "完全に削除され元に戻せません（フルディスクアクセスが必要）",

        // スマートクリーン
        "已使用": "使用中",
        "让你的 Mac 保持轻盈": "Mac をいつも軽やかに",
        "可用 %@ / 共 %@": "空き %@ / 合計 %@",
        "开始扫描": "スキャン開始",
        "扫描中…": "スキャン中…",
        "扫描范围": "スキャン範囲",
        "可清理空间 · 已勾选 %@": "解放できる容量・選択中 %@",
        "清理完成": "クリーン完了",
        "刚刚释放了 %@，移到废纸篓的内容可以恢复": "%@ を解放しました。ゴミ箱に移した項目は復元できます",
        "已选 %@/%@ 项": "%@/%@ 項目を選択",
        "另有 %@ 个较小项目": "ほかに小さな項目が %@ 個",
        "清理": "クリーン",
        "清理 %@": "%@ をクリーン",
        "确认清理 %@？": "%@ をクリーンしますか？",
        "废纸篓中的内容将被永久删除，无法恢复；其余项目会移到废纸篓。":
            "ゴミ箱の中身は完全に削除され、元に戻せません。その他の項目はゴミ箱に移動します。",
        "所选项目将移到废纸篓，需要时可以恢复。建议先退出相关应用。":
            "選択した項目はゴミ箱に移動し、必要なら復元できます。関連アプリは先に終了することをおすすめします。",
        "扫描是只读的，不会删除任何文件。": "スキャンは読み取り専用で、ファイルは削除されません。",
        "正在扫描…": "スキャン中…",
        "已扫描 %@/%@：%@": "スキャン済み %@/%@：%@",
        "很干净，没有找到可清理的内容 ✨": "きれいです。削除できるものはありません ✨",
        "找到 %@": "%@ 見つかりました",
        "，%@ 项属于运行中的应用，默认未勾选": "（実行中アプリの %@ 項目は未選択）",
        "正在清理…": "クリーン中…",
        "已释放 %@": "%@ を解放しました",
        "，%@ 项被保护或正在使用，已跳过": "（保護中または使用中の %@ 項目はスキップ）",

        // 大きなファイル
        "最小": "最小",
        "查找": "検索",
        "筛选路径": "パスで絞り込み",
        "找出占空间的大文件": "容量を占める大きなファイルを探す",
        "扫描主目录中的视频、安装包、压缩包等大文件。\n不会自动勾选任何文件，请自行确认后再删除。":
            "ホームフォルダ内の動画・インストーラ・圧縮ファイルなどを探します。\n自動では選択されないので、確認してから削除してください。",
        "没有找到大文件": "大きなファイルはありません",
        "试试降低大小阈值": "サイズのしきい値を下げてみてください",
        "在主目录中查找大文件（跳过系统资料库）": "ホームフォルダ内の大きなファイルを探します（~/Library は除外）",
        "正在查找大于 %@ MB 的文件…": "%@ MB を超えるファイルを検索中…",
        "没有找到大于 %@ MB 的文件": "%@ MB を超えるファイルはありません",
        "找到 %@ 个文件，共 %@，请手动勾选": "%@ 個のファイル（%@）が見つかりました。削除するものを選択してください",
        "移到废纸篓": "ゴミ箱に入れる",
        "移到废纸篓 %@": "%@ をゴミ箱に入れる",
        "将 %@ 个文件移到废纸篓？": "%@ 個のファイルをゴミ箱に入れますか？",
        "共 %@。这些是你的个人文件，请确认不再需要。可从废纸篓恢复。":
            "合計 %@。個人のファイルなので、不要であることを確認してください。ゴミ箱から復元できます。",
        "已移到废纸篓 %@": "%@ をゴミ箱に移動しました",
        "，%@ 项失败": "（%@ 項目は失敗）",

        // アンインストーラ
        "搜索应用": "アプリを検索",
        "计算中…": "計算中…",
        "彻底卸载应用": "アプリを完全にアンインストール",
        "选择左侧的应用，MacSweep 会找出它在资料库中的\n缓存、偏好设置、容器等残留文件，一并移到废纸篓。":
            "左のアプリを選ぶと、~/Library 内のキャッシュ・設定・コンテナなどの\n残りファイルを見つけて、まとめてゴミ箱に移動します。",
        "选择一个应用，查看它和它的残留文件": "アプリを選択すると、本体と残りファイルを表示します",
        "应用本体": "アプリ本体",
        "没有找到残留文件": "残りファイルはありません",
        "退出应用": "アプリを終了",
        "卸载": "アンインストール",
        "卸载 %@": "アンインストール %@",
        "卸载 %@？": "%@ をアンインストールしますか？",
        "应用及所选的 %@ 项相关文件（共 %@）将移到废纸篓，可以恢复。":
            "アプリと選択した関連ファイル %@ 項目（%@）をゴミ箱に移動します。復元できます。",
        "%@：找到 %@ 个相关文件": "%@：関連ファイルが %@ 個見つかりました",
        "已卸载 %@，释放 %@": "%@ をアンインストールし、%@ を解放しました",
        "无法移除 %@：可能需要管理员权限，请在访达中手动删除应用本体":
            "%@ を削除できませんでした。管理者権限が必要な可能性があります。Finder で削除してください。",

        // コマンドライン
        "轻量 macOS 清理工具（命令行模式均为只读）": "軽量 macOS クリーナー（CLI は読み取り専用）",
        "用法：": "使い方：",
        "打开图形界面": "アプリを開く",
        "预览可清理内容": "削除できる内容をプレビュー",
        "列出主目录中的大文件（默认 500 MB）": "ホームフォルダの大きなファイルを一覧（既定 500 MB）",
        "列出应用及其残留文件": "アプリと残りファイルを一覧",
        "显示版本": "バージョンを表示",
        "%@ 项": "%@ 項目",
        "  [运行中]": "  [実行中]",
        "共 %@ 个 ≥ %@ MB 的文件，合计 %@": "%2$@ MB 以上のファイル %1$@ 個、合計 %3$@",
        "未找到应用：%@（不支持 Apple 自带应用）": "アプリが見つかりません：%@（Apple 製アプリは対象外）",
        "合计 %@": "合計 %@",
        "合计可清理：%@（只读预览，未删除任何文件）": "削除可能な合計：%@（読み取り専用プレビュー、何も削除していません）",
    ]
}
