# Tinycast Extensions (`tiny-devkit` & `tiny-shortcuts`)

专为原生兼容 [Tinycast](https://github.com/abue-ammar/tinycast) 打造的开发者工具与日常效率快捷入口套件，采用**混合原生架构**：
- **无视图极速命令 (`no-view`) & 菜单栏 (`MenuBarExtra`)**：保留零延迟一键复制 UUID/时间戳/密码/Finder 路径。
- **纯原生 SwiftUI + AppKit 悬浮工作台 (`tinycast-devkit`)**：所有交互工具统一唤起单实例原生 macOS 悬浮窗口（毛玻璃半透明侧边栏、真多行编辑器、按钮实时交互、文件拖放、Native DatePicker、CoreImage 高清二维码预览），开启时仅占约 25–35 MB 内存，关闭窗口即自动退出释放至 **0 MB**（无 Chromium/WKWebView 进程开销）。

---

## 核心交互设计

1. **纯净搜索入口**：移除了 13 个交互工具在 Tinycast 搜索栏上的参数输入框，回车立即切换/唤起对应的悬浮工作台面板。
2. **直观点击复制且不关闭窗口**：工作台内的每一项结果都提供：
   - 直接**点击结果文本**复制；
   - 或点击右侧显式 **`[复制]`** 按钮复制；
   - 两种方式均**保持工作台窗口开启**并弹出 `✓ 已复制` 状态反馈。
3. **全局路由与置顶**：`⌘F` 聚焦侧边栏搜索框（支持按 `md5`/`jwt`/`aes` 等算法名直达对应子面板），右上角图钉图标可开启**窗口置顶悬浮**；未置顶且后台闲置 10 分钟或关闭窗口 (`⌘W`) 即自动退出进程。

---

## 功能列表

### 1. `tiny-devkit` — DevKit 开发者工具箱

| 命令 | 模式 | 功能亮点 |
| --- | --- | --- |
| **DevKit 原生多工具工作台** (`workbench`) | `no-view` → Studio | 默认打开「剪贴板智能工作台」，同窗侧边栏集成全部 12 款工具。 |
| **UUID 与 ID 生成器** (`uuid-generator`) | `no-view` → Studio | 支持 **UUID v1/v3/v4/v5/v6/v7/v8/Nil/Max** 与 **ULID / NanoID / KSUID / ObjectID**；格式/数量/分隔批量生成 + 下方实时结构解析与 10 种衍生变体。 |
| **时间戳转换** (`timestamp-converter`) | `no-view` → Studio | 实时秒表 + 自动识别 Unix `s`/`ms`/`μs`/`ns`、ISO 8601、紧凑日期、`+2h`/`today+1d` 相对表达式，配备原生 `DatePicker`、8 大时区与多语言代码片段。 |
| **Hash 与文件校验** (`hash-generator`) | `no-view` → Studio | 支持 **MD5、SHA-1/224/256/384/512、SHA-3、Keccak-256、BLAKE3、BLAKE2b/2s、国密 SM3、RIPEMD-160、CRC32/32C、Adler-32、FNV-1a、MurmurHash3**、HMAC 与期望值高亮比对；支持**拖拽/选取 GB 级本地文件 1 MB 流式分块计算**。 |
| **算法编解码 & 加解密** (`encode-decode`) | `no-view` → Studio | 4 合 1 子面板：双向工作台（Base64/URL/32/58、Hex、HTML、Unicode、Gzip/Deflate、JSON 转义、ROT13、Morse）、全算法速览、JWT 解析与 HS256/384/512 验签、原生 **AES-256-GCM / CBC** 加解密。 |
| **JSON 格式化与转换** (`json-formatter`) | `no-view` → Studio | 双栏编辑器：自动容错修复注释/单引号/尾逗号、2/4 空格美化、压缩、键排序、转换 **TypeScript 接口 / YAML / Query 参数**并可保存桌面。 |
| **色值转换与屏幕取色** (`color-converter`) | `no-view` → Studio | 解析与互转 Hex(3/4/6/8)、CSS4 `rgb`/`hsl`/`hwb`/`oklch`/`oklab`/`lab`/`lch`、SwiftUI/`NSColor`/`UIColor`、Android `#AARRGGBB`/Flutter、CMYK 与 148 CSS 命名色；支持 **macOS 系统屏幕吸管取色 (`NSColorSampler`)**、多空间滑块微调、**WCAG 2.1 + APCA 对比度及一键自动修复**、OKLCH 均匀 **Tailwind 50–950 色阶**、5 种配色方案、双色混合渐变与 4 种色盲模拟。 |
| **快速生成 UUID v4** (`quick-uuid-v4`) | `no-view` | 无视图即时生成并复制 UUID v4（支持 `Count` 参数）。 |
| **快速生成 UUID v7** (`quick-uuid-v7`) | `no-view` | 无视图即时生成时序有序 UUID v7 并复制。 |
| **快速复制当前时间戳** (`quick-timestamp`) | `no-view` | 无视图一键复制 Unix 秒/毫秒/ISO 时间戳。 |
| **DevKit 菜单栏工具** (`devkit-menubar`) | `menu-bar` | 常驻 macOS 菜单栏，快捷复制 UUID/时间戳、智能解码剪贴板或直达任意悬浮工具面板。 |

### 2. `tiny-shortcuts` — Quick Shortcuts 效率快捷入口

| 命令 | 模式 | 功能亮点 |
| --- | --- | --- |
| **密码与密钥生成器** (`password-generator`) | `no-view` → Studio | `SecRandomCopyBytes` 生成器：6–128 位滑块、字符集开关、Diceware 助记词短语、11 组常用密钥预设，默认启用 `ConcealedType` 隐私剪贴板保护。 |
| **快速生成强密码** (`quick-password`) | `no-view` | 无视图即时生成强密码并隐私复制（支持 `Len` 参数）。 |
| **文本格式与行处理** (`text-transform`) | `no-view` → Studio | 自动携带前台选中文本：字数/字节/行数统计、10 项行批处理（去重/排序/编号/JSON 数组等）与 11 种命名规范转换。 |
| **离线二维码生成器** (`qr-generator`) | `no-view` → Studio | 原生 `CIQRCodeGenerator` 离线生成清晰二维码，内置 Wi-Fi 配网二维码助手，一键保存 **SVG / 800px PNG** 到桌面。 |
| **Cron 表达式解析** (`cron-inspector`) | `no-view` → Studio | 解析 5/6 段 Cron 与 `@daily`/`@hourly` 等宏，展示中文语义、各字段拆解及未来 10 次触发时间。 |
| **本机 IP 与监听端口管理** (`network-ports`) | `no-view` → Studio | 展示活动网卡 IPv4/IPv6、按需查询公网 IP、实时列出 `lsof` TCP 监听端口并支持复制 URL、浏览器打开与带二次确认的结束进程。 |
| **剪贴板智能转换** (`smart-clipboard`) | `no-view` → Studio | 自动识别剪贴板内容并给出即刻转换结果与一键工具跳转入口。 |
| **在终端打开 Finder 目录** (`open-in-terminal`) | `no-view` | 无视图在 Terminal / iTerm / Ghostty / Warp 等终端打开当前 Finder 窗口目录。 |
| **复制 Finder 选中路径** (`copy-finder-path`) | `no-view` | 无视图一键复制当前 Finder 选中文件或文件夹的 POSIX 路径。 |

---

## 构建、验证与安装

```bash
pnpm install        # 安装 JS 构建依赖 (仅开发构建使用)
pnpm typecheck      # TypeScript 类型检查
pnpm test           # 运行 TS 共享引擎单元测试
pnpm build          # 编译 SwiftUI 原生应用 tinycast-devkit、图标并打包两个扩展至 dist/
pnpm verify         # Tinycast 运行时验证 20 个命令 + 原生二进制 --self-test
pnpm install-local  # 安装到 ~/Library/Application Support/com.abueammar.tinycast/extensions/
```

图形界面导入：打开 **Tinycast 设置 → 扩展 → Add from folder**，分别选取 `dist/tiny-devkit` 与 `dist/tiny-shortcuts`（构建包内置已赋权的 `assets/tinycast-devkit` 可执行文件）。
