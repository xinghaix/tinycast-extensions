# Tinycast Extensions (`tiny-devkit` & `tiny-shortcuts`)

[![CI](https://github.com/xinghaix/tinycast-extensions/actions/workflows/ci.yml/badge.svg)](https://github.com/xinghaix/tinycast-extensions/actions/workflows/ci.yml)
[![Release](https://github.com/xinghaix/tinycast-extensions/actions/workflows/release.yml/badge.svg)](https://github.com/xinghaix/tinycast-extensions/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: macOS 15+](https://img.shields.io/badge/macOS-15%2B%20(arm64%20%7C%20x86__64)-black)
![Swift 6 + TypeScript](https://img.shields.io/badge/Swift%206-SwiftUI%20%2B%20AppKit-orange)

专为原生兼容 [Tinycast](https://github.com/abue-ammar/tinycast) 打造的开发者工具箱与高频效率快捷入口扩展套件。

采用 **「无视图极速命令 + 纯原生 SwiftUI & AppKit 独立悬浮工作台」混合架构**：
- 零 Chromium / WKWebView 内存开销（打开工作台约占 ~30–40 MB 内存，关闭窗口即刻退出释放至 **0 MB**）。
- 100% 本地离线运算（仅在用户主动点击「查询公网 IP」时访问 `api.ipify.org`）。
- 兼容 Apple Silicon (`arm64`) 与 Intel (`x86_64`) 的 Universal 原生 `tinycast-devkit` 二进制。

---

## 目录

- [核心交互设计](#核心交互设计)
- [安装指南](#安装指南)
- [功能总览（20 个命令）](#功能总览20-个命令)
- [快捷键与使用技巧](#快捷键与使用技巧)
- [升级与卸载](#升级与卸载)
- [常见问题 (FAQ)](#常见问题-faq)
- [开发、验证与发布](#开发验证与发布)

---

## 核心交互设计

1. **纯净无干扰搜索入口**：所有 13 个交互工具均以 `no-view` 极速启动器注册，去除了搜索栏参数占位框，选中回车即可直接唤起对应工具页。
2. **内核级 `flock` 单实例悬浮窗**：无论从 Tinycast 搜索栏还是菜单栏连续点击多个工具，始终复用同一个原生悬浮窗秒切面板，绝不会同时弹出多个重复窗口。
3. **点击即复制且保持窗口**：工作台内的每一项结果均支持：
   - **直接左键点击结果文本**复制；
   - 或点击右侧显式 **`[复制]`** 按钮复制；
   - 两种方式均保留窗口开启并给出 `✓ 已复制` 反馈，方便继续对比或衍生计算。
4. **随时置顶与智能识别**：`⌘F` 聚焦侧边栏搜索（搜 `md5` / `jwt` / `aes` / `wcag` 直达对应模块），右上角图钉可置顶悬浮；未置顶且后台闲置 10 分钟或按下 `⌘W` 关闭窗口即自动退出进程。

---

## 安装指南

> **前置要求**：macOS 15.0+（Sequoia 及以上，支持 Apple Silicon 与 Intel）并已安装 [Tinycast](https://github.com/abue-ammar/tinycast)。

### 方式一：下载 GitHub Release 预编译包（推荐，免开发环境）

无需安装 Xcode 或 Node.js，直接安装构建好的 Universal 扩展包：

1. 前往本仓库 [Releases 页面](https://github.com/xinghaix/tinycast-extensions/releases/latest) 下载：
   - **完整整合包（推荐）**：`tinycast-extensions-bundle-vX.Y.Z-macos-universal.zip`
   - 或按需单独下载 `tiny-devkit-vX.Y.Z-macos-universal.zip` / `tiny-shortcuts-vX.Y.Z-macos-universal.zip`
2. 解压下载的压缩包，任选以下一种方式导入：
   - **图形界面导入**：打开 **Tinycast 设置 → 扩展 → 安装 → `Add from folder` (选取…)**，分别选取解压出的 `tiny-devkit` 和 `tiny-shortcuts` 文件夹。
   - **脚本一键安装**：在解压目录打开终端执行 `./install.sh`（自动关闭旧工作台进程并安装至 Tinycast 扩展目录）。
3. **重启一次 Tinycast**（或在设置页刷新扩展），即可使用全部 20 个命令与菜单栏工具。

### 方式二：从源码编译安装

需要本机已安装 Xcode Command Line Tools (`swiftc` Swift 6+)、Node.js `>= 22` 与 `pnpm`：

```bash
git clone https://github.com/xinghaix/tinycast-extensions.git
cd tinycast-extensions
pnpm install --frozen-lockfile
pnpm build          # 仅编译当前架构（如需通用二进制可执行 pnpm build:universal）
pnpm install-local  # 安装到 ~/Library/Application Support/com.abueammar.tinycast/extensions/
```

安装后同样重启一次 Tinycast，或者使用 `Add from folder` 直接选取构建生成的 `dist/tiny-devkit` 与 `dist/tiny-shortcuts`。

> **为什么不使用 Tinycast 的 `Install from GitHub`？**
> Tinycast 内置的 `Install from GitHub` 仅支持单一根目录包含 `package.json` 的纯 JS/Raycast 扩展构建；本仓库为多扩展 Monorepo 且内置原生的 SwiftUI Mach-O 编译流程，因此请使用上述 **Release 预编译包 (`Add from folder`)** 或 **源码构建 (`pnpm build`)**。

---

## 功能总览（20 个命令）

### 1. `tiny-devkit` — DevKit 开发者工具箱（11 个命令）

| 命令 | 模式 | 功能亮点 |
| --- | --- | --- |
| **DevKit 原生多工具工作台** (`workbench`) | `no-view` → Studio | 默认打开「剪贴板智能工作台」，侧边栏同窗集成全部 12 款开发者工具。 |
| **UUID 与 ID 生成器** (`uuid-generator`) | `no-view` → Studio | **UUID v1/v3/v4/v5/v6/v7/v8/Nil/Max** + **ULID / NanoID / KSUID / ObjectID**；格式切换、1–50 批量（按行 / JSON / CSV / SQL IN）及实时结构拆解与 10 种变体。 |
| **时间戳转换** (`timestamp-converter`) | `no-view` → Studio | 实时秒表 + 自动识别 Unix `s`/`ms`/`μs`/`ns`、ISO 8601、紧凑日期、`+2h`/`today+1d` 相对表达式，配备原生 `DatePicker`、8 大时区与 JS/Py/Go/SQL 代码片段。 |
| **Hash 与文件校验** (`hash-generator`) | `no-view` → Studio | 支持 **MD5、SHA-1/224/256/384/512、SHA-3、Keccak-256、BLAKE3、BLAKE2b/2s、国密 SM3、RIPEMD-160、CRC32/32C、Adler-32、FNV-1a、MurmurHash3**、HMAC 与期望值高亮比对；支持**拖拽/选取本地大文件 1 MB 流式分块计算**。 |
| **算法编解码 & 加解密** (`encode-decode`) | `no-view` → Studio | 4 合 1 子面板：双向工作台（Base64/URL/32/58、Hex、URL、HTML、Unicode、Gzip/Deflate、JSON 转义、ROT13、Morse）、全算法速览、JWT 解析与 HS256/384/512 验签、原生 **AES-256-GCM / CBC** 加解密。 |
| **JSON 格式化与转换** (`json-formatter`) | `no-view` → Studio | 双栏编辑器：容错修复注释/单引号/尾逗号、2/4 空格美化、压缩、键排序、转 **TypeScript 接口 / YAML / Query 参数** 并一键保存桌面。 |
| **色值转换与屏幕取色** (`color-converter`) | `no-view` → Studio | Hex/CSS4(`rgb`/`hsl`/`hwb`/`oklch`/`oklab`/`lab`/`lch`)/SwiftUI/`NSColor`/Android/CMYK 与 148 命名色互转；**macOS 屏幕吸管取色 (`NSColorSampler`)**、5 空间实时滑块、**WCAG 2.1 + APCA 对比度及一键达标修复**、Tailwind 50–950 色阶、5 种配色方案、渐变混合与 4 种色盲模拟。 |
| **快速生成 UUID v4** (`quick-uuid-v4`) | `no-view` | 无视图即时生成并复制 UUID v4（支持 `Count` 参数批量复制）。 |
| **快速生成 UUID v7** (`quick-uuid-v7`) | `no-view` | 无视图即时生成时序有序 UUID v7 并复制。 |
| **快速复制当前时间戳** (`quick-timestamp`) | `no-view` | 无视图一键复制当前 Unix 秒/毫秒/ISO 时间戳。 |
| **DevKit 菜单栏工具** (`devkit-menubar`) | `menu-bar` | 常驻 macOS 菜单栏：快速生成 UUID/时间戳、智能解码剪贴板颜色/JWT/Base64/时间戳或一键直达工作台。 |

### 2. `tiny-shortcuts` — Quick Shortcuts 效率快捷入口（9 个命令）

| 命令 | 模式 | 功能亮点 |
| --- | --- | --- |
| **密码与密钥生成器** (`password-generator`) | `no-view` → Studio | `SecRandomCopyBytes` 生成器：6–128 位滑块、字符集开关、Diceware 助记词短语、11 组常用密钥预设，默认标记 `ConcealedType` 不进剪贴板历史。 |
| **快速生成强密码** (`quick-password`) | `no-view` | 无视图即时生成高强度密码并隐私复制（支持 `Len` 参数）。 |
| **文本格式与行处理** (`text-transform`) | `no-view` → Studio | 自动携带当前前台选中文本：实时字符/字节/词行统计、10 种行批处理（支持回填链式操作）与 11 种编程命名规范转换。 |
| **离线二维码生成器** (`qr-generator`) | `no-view` → Studio | 原生 `CIQRCodeGenerator` 离线生成高清二维码、内置 Wi-Fi 配网二维码助手，一键导出矢量 **SVG / 800px PNG** 到桌面。 |
| **Cron 表达式解析** (`cron-inspector`) | `no-view` → Studio | 解析 5/6 段 Cron 与 `@daily`/`@hourly` 等宏，展示中文语义、各字段拆解及未来 10 次触发时间。 |
| **本机 IP 与监听端口管理** (`network-ports`) | `no-view` → Studio | 查看活动网卡 IPv4/IPv6、按需查询公网 IP、实时搜索 `lsof` TCP 监听端口并支持复制 URL、浏览器打开与带二次确认的 `SIGTERM` 结束进程。 |
| **剪贴板智能转换** (`smart-clipboard`) | `no-view` → Studio | 自动识别剪贴板内容（UUID / 时间戳 / JWT / JSON / 颜色 / Base64 / Hex / URL）并给出即刻结果与专项跳转。 |
| **在终端打开 Finder 目录** (`open-in-terminal`) | `no-view` | 无视图在 Terminal / iTerm / Ghostty / Warp / Kitty / WezTerm 打开当前 Finder 窗口目录。 |
| **复制 Finder 选中路径** (`copy-finder-path`) | `no-view` | 无视图一键复制当前 Finder 选中文件或目录的 POSIX 路径。 |

---

## 快捷键与使用技巧

- **工作台通用快捷键**：
  - `⌘F`：聚焦左侧全局搜索框（支持输入 `oklch`、`md5`、`jwt`、`aes` 等关键字快速定位）
  - `⌘W` / `⌘Q`：关闭窗口并退出进程（立即归零内存）
  - 右上角图钉图标：开启或取消**置顶悬浮**
  - 右上角剪贴板图标：随时将当前系统剪贴板文本载入当前激活工具
- **推荐 Tinycast 别名 / 热键配置**：在 Tinycast 设置中为高频无视图命令配置别名或快捷键，如 `uv7`（快速生成 UUID v7）、`ts`（快速复制当前时间戳）、`pw`（快速生成强密码）、`color`（色值转换与屏幕取色）、`sc`（剪贴板智能转换）。

---

## 升级与卸载

- **升级**：下载新版本 Release 重新导入（或拉取最新代码后运行 `pnpm build && pnpm install-local`），建议升级后重启 Tinycast 以刷新 `package.json` 中的新命令。
- **卸载**：在 **Tinycast 设置 → 扩展 → 已安装** 中直接点击卸载即可；若曾使用工作台生成临时锁文件，重启后或手动清理 `/tmp/tinycast-devkit-*` 即可。

---

## 常见问题 (FAQ)

- **Q：macOS 首次打开提示「无法验证开发者 / 已损坏」怎么办？**
  从浏览器直接下载压缩包时，macOS 可能附加 `com.apple.quarantine` 隔离属性。在解压目录执行以下命令移除隔离属性后重新导入即可：
  ```bash
  xattr -dr com.apple.quarantine tiny-devkit tiny-shortcuts
  ```
- **Q：为什么新增/更新命令后 Tinycast 搜索栏还是旧列表或旧参数框？**
  Tinycast 在启动时读取扩展清单到内存；每次安装或更新扩展后，请**完整退出并重启 Tinycast**（或在设置页刷新扩展）。

---

## 开发、验证与发布

仓库 `main` 分支受保护，所有合入需通过 GitHub Actions `CI` 门禁（`Hygiene, Typecheck & Tests` + `Build, Test & Verify (macOS)`）：

```bash
pnpm install --frozen-lockfile
pnpm run check:hygiene      # 检查 Manifest/资源完整性，拦截本地路径与敏感信息
pnpm typecheck              # TypeScript 类型检查
pnpm test                   # 运行 TS 共享引擎单元测试
pnpm build:universal        # 构建 arm64 + x86_64 Universal 二进制与全部 20 个扩展包
pnpm verify:ci              # 独立模式验证（所有 20 个 CJS 导出、codesign、--self-test、5 进程并发 flock）
pnpm verify                 # 若同级存在 ../tinycast，自动额外运行完整 Tinycast runtime harness
```

### 发布新版本 (Release)

维护者打上以 `v` 开头的语义化版本标签并推送（或在 GitHub Actions 页面手动触发 `Release` 工作流）：

```bash
git tag v1.0.0
git push origin v1.0.0
```

[Release 工作流](.github/workflows/release.yml) 将自动完成全量门禁检查、编译 Universal 原生二进制，并打包发布三个独立/整合 `.zip` 与 `SHA256SUMS.txt`。

---

## 安全与许可证

- 隐私与安全策略请参阅 [SECURITY.md](SECURITY.md)，贡献规范请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 基于 [MIT License](LICENSE) 开源；特别感谢 [Tinycast](https://github.com/abue-ammar/tinycast) 提供原生高效的扩展运行时。
