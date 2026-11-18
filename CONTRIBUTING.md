# 贡献指南 (Contributing)

感谢关注并为 `tinycast-extensions` 贡献代码！

## 开发环境要求

- **操作系统**：macOS 15.0+（Swift 6.0+ 工具链，Xcode 16+ / Command Line Tools）
- **Node.js**：>= 22.0.0（内置 `--experimental-strip-types` 用于测试运行器）
- **包管理器**：`pnpm` >= 9

## 仓库结构

```text
tinycast-extensions/
├── extensions/
│   ├── tiny-devkit/        # DevKit 开发者工具箱清单、图标、菜单栏与无视图启动器
│   └── tiny-shortcuts/     # Quick Shortcuts 效率快捷入口清单、图标与无视图启动器
├── native/devkit-app/
│   └── Sources/            # 纯原生 SwiftUI + AppKit 悬浮工作台源码 (tinycast-devkit)
├── packages/shared/        # TS 共享算法（菜单栏/无视图快捷入口使用）与单元测试
└── scripts/                # 图标生成、跨架构构建、本地安装、运行时验证与卫生检查脚本
```

## 开发与提交流程

1. **创建特性分支**：`main` 分支受保护，禁止直接推送；请从 `main` 切出 `feat/...` 或 `fix/...` 分支后提交 Pull Request。
2. **本地验证门禁**：提交 PR 前请在本地完整运行以下命令（均须退出码 `0`）：

```bash
pnpm install --frozen-lockfile
pnpm run check:hygiene      # 检查 JSON 合法性、图标资源完整性，确保无本地路径与密钥泄露
pnpm typecheck              # TypeScript 严格类型检查
pnpm test                   # 共享引擎单元测试
pnpm build                  # 本机架构构建（或 pnpm build:universal 构建 Universal 二进制）
pnpm verify                 # 运行时验证（若同级存在 ../tinycast 则运行完整 Tinycast harness，否则自动运行 --standalone）
```

3. **编码与文档规范**：
   - **Swift 侧**：开启 `-swift-version 6` 严格并发检查；UI 操作不得自动关闭工作台窗口，结果卡片需保留直点文本和右侧 `[复制]` 双通道；大文件读取必须使用流式分块防止 OOM。
   - **TypeScript 侧**：`no-view` 工作台启动器统一通过 `launchDevKitStudio` 启动，不得重新引入搜索栏 `"arguments"` 胶囊；避免在扩展代码中引入真实路径或个人隐私信息。
   - 新增或变更命令名称、热键或配置项时，同步更新 `README.md` 与 `scripts/verify-tinycast.mjs`。
