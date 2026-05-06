# FileLens

> 简体中文 · [English](README.md)

为 macOS 上任何文件夹加一层**非破坏性**的标签视图。FileLens 监听你指定的文件夹，按你定义的规则给里面的文件打标签并分组展示——但**从不移动、重命名或修改原始文件**。

> 文件原地不动，FileLens 只是给你换一副"镜片"看它们。

## 为什么做这个

你的 `~/Downloads`（或者 `~/Desktop` 这种乱扔文件夹）里堆着几百个文件，一直没整理。市面上的工具要么是物理搬运型（Hazel、Spotless ——规则配错就翻车），要么太弱（Finder 智能文件夹）。

FileLens 填中间。你指给它一个文件夹，它根据你定的规则按类型 / 文件名 / 时间给每个文件打标签，给你一个 Finder 风格的侧栏，按标签切片浏览。**原文件一根头发都不动**。

## 功能

- **多工作区** —— 监听任意多个文件夹，每个工作区有自己独立的规则集
- **13 条内置规则**：安装包、图片、视频、音频、PDF、文档、压缩包、代码、截图、大文件、新加入、长期未动、下载中
- **自定义规则**：按扩展名 / 文件名 / 大小 / 时间 / 种类，all/any 组合
- **手动标签** —— 右键给任意文件打 ad-hoc 标签
- **三种视图模式**（与 Finder 对齐）：图标 ⌘1 / 列表 ⌘2 / 画廊 ⌘4
- **列表按时间分组**：今天 / 过去 3 / 7 / 15 天 / 1 个月 / 3 / 6 个月 / 1 年 / 更早
- **原生交互**：快速预览（Space）、在 Finder 中显示（⌘R）、移到废纸篓（⌘⌫）、打开（⌘↩）、拖出到其他 App
- **Inspector 面板**（⌘I）显示元数据 + 标签
- **搜索**（⌘F）按文件名过滤
- **系统文件图标** —— 跟 Finder 一致
- **FSEvents 实时更新** —— 新下载的文件立刻出现，自动打标签
- **设置**（⌘,）：外观（浅色/深色/跟随系统）+ 语言（简体中文/English/跟随系统）
- **自动检查更新**（基于 GitHub Releases）

**非破坏性承诺**：FileLens 唯一会动文件的操作就是"移到废纸篓"（你主动点击的）。任何规则都不会移动、重命名、复制或修改文件本身。

## 安装

预编译版本（如已发布）见 [Releases 页面](https://github.com/lifedever/file-lens/releases/latest)：

| Mac | 下载 |
|---|---|
| Apple Silicon (M1/M2/M3/M4) | `FileLens-X.Y.Z-arm64.dmg` |
| Intel | `FileLens-X.Y.Z-x86_64.dmg` |

打开 DMG，把 FileLens.app 拖到 `/Applications`。

**首次打开（Gatekeeper）**：因为是 ad-hoc 签名，macOS 第一次会拒绝打开。在终端运行：

```bash
sudo xattr -rd com.apple.quarantine /Applications/FileLens.app
```

之后从启动台点开即可。

## 自己编译

环境：macOS 14+（Sonoma）、Xcode 15+、[xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）、[librsvg](https://gitlab.gnome.org/GNOME/librsvg)（生成图标用，`brew install librsvg`）。

```bash
git clone https://github.com/lifedever/file-lens.git
cd file-lens

xcodegen generate                       # 由 project.yml 生成 FileLens.xcodeproj
./Scripts/dev.sh                        # Debug 编译 + 打开
./Scripts/release.sh 0.1.0 arm64        # 打 Release DMG（也可 x86_64 / universal）
```

## 技术栈

macOS 14+ · SwiftUI + AppKit · SwiftData · QuickLookThumbnailing · FSEvents · DMG 直发，ad-hoc 签名，不开沙盒

## License

MIT —— 见 [LICENSE](LICENSE)

---

## 捐助

如果 FileLens 帮你省了时间，欢迎请我喝杯咖啡支持继续迭代 ☕

- GitHub Sponsors：<https://github.com/sponsors/lifedever>
- 支付宝 / 微信：见仓库主页二维码

或者直接给仓库点一个 ⭐ ，对我也是巨大鼓励。
