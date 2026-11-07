<div align="center">

<img src="docs/icon.png" width="128" alt="MacSweep icon">

# MacSweep

**A lightweight, safe, open-source cleaner for macOS**

**English** · [简体中文](README.zh-CN.md) · [日本語](README.ja.md)

Pure SwiftUI · ~2 MB download · No dependencies · No network access · Moves files to the Trash so you can restore them

</div>

---

## 🧰 Three tools in one

| | Tool | What it does |
| --- | --- | --- |
| ✨ | **Smart Clean** | Scans 8 kinds of clutter (caches, logs, developer junk and more) and cleans the categories you pick |
| 🔍 | **Large Files** | Finds files over 100 MB / 500 MB / 1 GB / 5 GB in your home folder, with a path filter |
| 🗑️ | **Uninstaller** | Removes an app together with its caches, preferences, containers and other leftovers in `~/Library` |

## ✨ Features

- **Three languages**: 中文 / 日本語 / English. Follows your system language, or switch instantly in Settings (the CLI follows too)
- **Modern UI**: sidebar navigation, disk usage ring, colorful category cards, size bars, dark mode
- **Custom background**: upload any image in Settings, or drop one onto the window; adjust dim and blur
- **Scan first, clean later**: scanning is read-only; nothing happens until you confirm
- **Restorable**: files go to the Trash by default. Only "Empty Trash" deletes permanently, with an extra confirmation
- **Protects running apps**: caches of running apps are tagged "Running" and left unselected
- **Allow-listed rules**: only cleans items inside fixed folders, never the folders themselves, and never follows symlinks
- **Parallel scanning**: categories and folder sizes are computed concurrently, usually in under a second
- **Conservative leftover matching**: leftovers are matched by bundle ID with strict boundaries so other apps are never hit; Apple apps cannot be uninstalled
- **Lifetime stats**: keeps track of how much space you have freed
- **Command line**: read-only `--scan`, `--large` and `--leftovers`, plus `--json` output for scripts
- **Tiny codebase**: 5 Swift files built directly with `swiftc`, no Xcode project needed

## 🧹 Cleanup categories

| Category | Location | Default |
| --- | --- | :---: |
| User Caches | `~/Library/Caches` | ✅ |
| Log Files | `~/Library/Logs` | ✅ |
| App Caches | `~/Library/Application Support/*/{Cache,Code Cache,GPUCache,CachedData}` | ✅ |
| Xcode Build Files | `DerivedData`, simulator caches, `iOS DeviceSupport` | ✅ |
| Developer Caches | npm, yarn, pnpm, Gradle, CocoaPods, Cargo | ✅ |
| Conda Packages | `anaconda3/pkgs/*.conda` (same as `conda clean -p`) | ⬜ |
| Old Installers | `.dmg / .pkg / .iso` in `~/Downloads` older than 30 days | ⬜ |
| Trash | `~/.Trash` (permanent deletion) | ⬜ |

Your selection is remembered. To add a category, add one rule to `allRules` in `Sources/Engine.swift`.

## 📦 Install

### Option 1: Download

Download `MacSweep-x.y.z.zip` from [Releases](https://github.com/DevX-star/MacSweep/releases), unzip it and drag the app into Applications. Works on Apple Silicon and Intel with macOS 13 or later.

> The app is not notarized by Apple. If macOS says it can't verify the developer, right-click the app and choose Open, or run:
> ```bash
> xattr -dr com.apple.quarantine /Applications/MacSweep.app
> ```

### Option 2: Build from source

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/DevX-star/MacSweep.git
cd MacSweep
./build.sh              # build for this Mac → build/MacSweep.app
./build.sh universal    # build for Apple Silicon + Intel and create a zip
open build/MacSweep.app
```

## ⌨️ Command line

```bash
MacSweep.app/Contents/MacOS/MacSweep --scan                # preview what can be cleaned
MacSweep.app/Contents/MacOS/MacSweep --large 1000          # list files ≥ 1 GB
MacSweep.app/Contents/MacOS/MacSweep --leftovers Slack     # list an app and its leftovers
MacSweep.app/Contents/MacOS/MacSweep --scan --json         # JSON output
MacSweep.app/Contents/MacOS/MacSweep --help
```

The command line is **read-only** and never deletes anything. Use the app to clean.

## 🗂️ Code layout

| File | Contents |
| --- | --- |
| `Sources/Engine.swift` | Rules, scanning, large file search, leftover matching, deletion (UI-independent) |
| `Sources/Models.swift` | State for each page (ObservableObject) |
| `Sources/Views.swift` | SwiftUI views and components |
| `Sources/Localization.swift` | Translations: `t("Chinese source text")` looks up a table; add a language by adding a table |
| `Sources/App.swift` | Entry point and command line mode |

## 🔒 Permissions

- No admin rights needed. MacSweep only touches your user folder (plus `/opt/*conda*/pkgs`)
- Apps installed by an administrator may need to be deleted manually in Finder
- Scanning the Trash requires adding MacSweep under **System Settings → Privacy & Security → Full Disk Access**
- No network access and no data collection. Custom backgrounds are stored in `~/Library/Application Support/MacSweep/`

## 🙏 Credits

- [tw93/Mole](https://github.com/tw93/Mole) — category-based deep cleaning
- [alienator88/Pearcleaner](https://github.com/alienator88/Pearcleaner) — app uninstalling with leftover search and a safety-first design
- [mac-cleanup/mac-cleanup-py](https://github.com/mac-cleanup/mac-cleanup-py) — rule-based cleanup and dry runs

## 📄 License

[MIT](LICENSE)
