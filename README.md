<div align="center">

<img src="docs/icon.png" width="128" alt="MacSweep icon">

# MacSweep

**轻量、安全、开源的 macOS 清理小工具**

中文 · 日本語 · English

纯 SwiftUI · 安装包约 2 MB · 无依赖 · 无联网 · 默认移到废纸篓可恢复

</div>

---

## 🧰 三大功能

| | 功能 | 说明 |
| --- | --- | --- |
| ✨ | **智能清理** | 一键扫描缓存、日志、开发工具垃圾等 8 类可清理内容，按类别勾选清理 |
| 🔍 | **大文件查找** | 在主目录中找出 100 MB / 500 MB / 1 GB / 5 GB 以上的文件，支持路径筛选 |
| 🗑️ | **应用卸载** | 卸载应用并找出它在资料库中的缓存、偏好设置、容器等残留文件（类似 Pearcleaner） |

## ✨ 特性

- **三语切换**：中文 / 日本語 / English，可跟随系统或在「设置」中即时切换（命令行同样生效）
- **现代界面**：侧边栏导航、磁盘占用环形图、彩色类别卡片、大小占比条，支持深色模式
- **自定义背景**：侧边栏「设置」中上传任意图片（或直接拖进窗口），可调遮罩和模糊；图片保存在 `~/Library/Application Support/MacSweep/`
- **先扫描、后清理**：扫描完全只读，勾选确认后才动手
- **可恢复**：默认移到废纸篓，误删可以从废纸篓找回；只有“清空废纸篓”是永久删除，并会二次确认
- **保护运行中的应用**：属于正在运行的应用的缓存会标记为「运行中」，默认不勾选
- **白名单规则**：只清理固定目录下的子项，不删除目录本身，不跟随符号链接
- **并行扫描**：多类别并发、子目录并行计算大小，通常 1 秒内完成
- **残留匹配保守**：应用残留只按 bundle id（带分隔边界）精确匹配，避免误伤其他应用；Apple 自带应用不可卸载
- **累计统计**：记录累计释放的空间
- **命令行模式**：`--scan`、`--large`、`--leftovers` 只读预览，`--json` 输出方便脚本集成
- **极致轻量**：4 个 Swift 源文件，`swiftc` 直接编译，无需 Xcode 工程

## 🧹 清理类别

| 类别 | 路径 | 默认 |
| --- | --- | :---: |
| 用户缓存 | `~/Library/Caches` | ✅ |
| 日志文件 | `~/Library/Logs` | ✅ |
| 应用内缓存 | `~/Library/Application Support/*/{Cache,Code Cache,GPUCache,CachedData}` | ✅ |
| Xcode 构建产物 | `DerivedData`、模拟器缓存、`iOS DeviceSupport` | ✅ |
| 开发工具缓存 | npm、yarn、pnpm、Gradle、CocoaPods、Cargo | ✅ |
| Conda 安装包缓存 | `anaconda3/pkgs/*.conda`（等同 `conda clean -p`） | ⬜ |
| 旧安装包 | `~/Downloads` 中 30 天前的 `.dmg / .pkg / .iso` | ⬜ |
| 废纸篓 | `~/.Trash`（永久删除） | ⬜ |

勾选状态会被记住。想新增类别，只需在 `Sources/Engine.swift` 的 `allRules` 中加一条规则。

## 🗂️ 代码结构

| 文件 | 内容 |
| --- | --- |
| `Sources/Engine.swift` | 清理规则、扫描、大文件查找、残留匹配、删除（与 UI 无关） |
| `Sources/Models.swift` | 各页面的状态（ObservableObject） |
| `Sources/Views.swift` | SwiftUI 界面与组件 |
| `Sources/App.swift` | 入口与命令行模式 |
| `Sources/Localization.swift` | 多语言：`t("中文原文")` 查表翻译，新增语言只需加一张表 |

## 📦 安装

### 方式一：下载

从 [Releases](https://github.com/DevX-star/MacSweep/releases) 下载 `MacSweep-x.y.z.zip`，解压后拖到「应用程序」。

> 应用未经 Apple 公证，首次打开若提示“无法验证开发者”，请右键 → 打开，或执行：
> ```bash
> xattr -dr com.apple.quarantine /Applications/MacSweep.app
> ```

### 方式二：从源码构建

需要 macOS 13+ 和 Xcode 命令行工具（`xcode-select --install`）。

```bash
git clone https://github.com/DevX-star/MacSweep.git
cd MacSweep
./build.sh              # 构建当前架构 → build/MacSweep.app
./build.sh universal    # 构建 Apple Silicon + Intel 通用版，并打包 zip
open build/MacSweep.app
```

## ⌨️ 命令行

```bash
MacSweep.app/Contents/MacOS/MacSweep --scan     # 预览可清理内容（只读）
MacSweep.app/Contents/MacOS/MacSweep --large 1000          # 列出 ≥ 1 GB 的大文件
MacSweep.app/Contents/MacOS/MacSweep --leftovers Slack     # 列出应用及其残留文件
MacSweep.app/Contents/MacOS/MacSweep --scan --json         # JSON 格式输出
MacSweep.app/Contents/MacOS/MacSweep --help
```

命令行模式**只读**，不会删除任何文件；清理请使用图形界面。

## 🔒 权限说明

- 无需管理员权限，只处理当前用户目录（卸载 root 安装的应用时可能需要在访达中手动删除）（以及 `/opt/*conda*/pkgs`）
- 扫描“废纸篓”需要在 **系统设置 → 隐私与安全性 → 完全磁盘访问权限** 中添加 MacSweep
- 不联网、不收集任何数据

## 🙏 致谢与参考

- [tw93/Mole](https://github.com/tw93/Mole) — 按类别深度清理的思路
- [alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner) — 应用卸载与残留查找、安全优先的设计
- [mac-cleanup/mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) — 规则化清理与 dry-run

## 📄 License

[MIT](LICENSE)
