# mac-qr-scanner 设计文档

- 日期：2026-06-21
- 状态：已批准方案，待用户复审 spec

## 背景与目标

macOS 系统原生只能在「预览 / 快速查看 / Safari」里**打开图片后**识别二维码，且主要把内容当网址处理；无法在 Finder 里直接右击图片文件就识别。App Store 上的同类工具多为「拖拽 / 复制粘贴 / 浏览器扩展」，几乎没有「Finder 右键菜单识别」的产品——这正是本项目要填补的空白。

**目标**：在 Finder 里右击图片，通过「快速操作」子菜单的「识别二维码」项，把二维码内容复制到剪贴板，并给系统通知。零外部依赖、零安装负担。

**非目标（YAGNI）**：摄像头扫码、生成二维码、历史记录、独立 GUI 主窗口、二维码内容的智能解析（WiFi/vCard 等结构化处理）。v1 只做「识别并复制原始字符串」。

## 行为约定

针对当前选中的一张或多张图片，聚合识别出的全部二维码内容后：

- **0 个** → 系统通知「未发现二维码」，不改动剪贴板
- **1 个** → 静默复制到剪贴板 + 通知「已复制：<内容预览>」
- **多个** → 弹出选单（`choose from list`）让用户挑一个 → 复制 + 通知；用户取消则不改动剪贴板

## 架构

两层，职责清晰隔离：

```
Finder 右击图片 →「快速操作 → 识别二维码」
        │  (传入图片文件路径作为参数)
        ▼
Automator 快速操作 (.workflow)
        │  仅一行：exec 已安装的胶水脚本
        ▼
qr-quick-action.sh  (胶水层：UX 编排)
        │  调用 qrscan 拿到 payloads
        ├─ 0 行 → osascript 通知
        ├─ 1 行 → pbcopy + 通知
        └─ >1 行 → osascript choose from list → pbcopy + 通知
        ▼
qrscan  (纯识别 CLI：图片路径 → 按行输出二维码内容)
        使用 Apple Vision: VNDetectBarcodesRequest(symbologies=[.qr])
```

### 组件 1：`qrscan`（Swift 命令行工具）

- **职责单一**：只做识别，不碰剪贴板/通知/GUI，便于独立测试。
- **输入**：一个或多个图片文件路径作为命令行参数。
- **处理**：逐个文件用 `CGImageSource` 读图 → `VNImageRequestHandler` 跑 `VNDetectBarcodesRequest`（`symbologies = [.qr]`）→ 收集 `payloadStringValue`。
- **输出**：每个识别到的二维码内容占一行，打印到 stdout；按出现顺序去重（相同内容只输出一次）。
- **退出码**：`0` = 至少识别到一个；`1` = 一个都没识别到；`2` = 参数/读图错误。
- **错误处理**：单个文件读不了 → 往 stderr 打告警、跳过、继续处理其余文件。
- **构建**：单文件 `Sources/qrscan/main.swift`，用 `swiftc` 编译出 `qrscan` 二进制，无需 Xcode 工程。

### 组件 2：`scripts/qr-quick-action.sh`（胶水脚本）

- 接收图片路径参数，调用同目录下的 `qrscan`，按上面「行为约定」编排 `pbcopy` 与 `osascript`（通知 + 多码选单）。
- 找不到 `qrscan` 时 → 通知「qrscan 未安装，请运行 install.sh」。
- 通知里的内容预览截断到约 100 字符，避免过长。

### 组件 3：Automator 快速操作（`.workflow`）

- 「工作流程接收当前的 **图像文件** 位于 **访达**」。
- 一个「运行 Shell 脚本」动作，**传递输入：作为参数**，内容仅一行：
  `exec "$HOME/Library/Application Support/mac-qr-scanner/qr-quick-action.sh" "$@"`
- 导出的 `.workflow` 纳入版本控制（`automator/识别二维码.workflow`），安装时拷贝到 `~/Library/Services/`。

### 组件 4：`install.sh` + `Makefile`

- `make build` → 用 swiftc 编译 `qrscan`。
- `make test` → 跑 fixture 测试。
- `install.sh` →（1）编译 qrscan；（2）把 `qrscan` 和 `qr-quick-action.sh` 拷到 `~/Library/Application Support/mac-qr-scanner/`；（3）把 `.workflow` 拷到 `~/Library/Services/`。安装到用户目录，**无需 sudo**。

## 数据流

图片路径（来自 Finder 选择）→ Automator 作为参数透传 → `qr-quick-action.sh` → `qrscan` 输出 payloads（换行分隔）→ 脚本判定 复制/选单/通知。

## 测试策略

- **fixture 测试**（`tests/`）：提交几张已知内容的二维码 PNG（URL、纯文本、含中文、多码图、无码图），`tests/run-tests.sh` 对每张跑 `qrscan` 并比对 stdout 与期望 txt、检查退出码。
- **手动端到端**：安装后在 Finder 右击各类图片，验证 0/1/多 三种路径与通知文案。

## 仓库结构

```
mac-qr-scanner/
├── README.md
├── .gitignore
├── Makefile
├── install.sh
├── Sources/qrscan/main.swift          # Vision 识别 CLI
├── scripts/qr-quick-action.sh          # 胶水层
├── automator/识别二维码.workflow/        # 受版本控制的快速操作
└── tests/
    ├── fixtures/                        # 二维码样图 + 期望输出
    └── run-tests.sh
```

## 开放问题 / 假设

- 假设目标系统为 macOS Ventura 及以上（Vision 的 QR 识别成熟稳定）。
- 安装位置用 `~/Library/Application Support/mac-qr-scanner/`，避免 sudo；若后续要做正式分发包再考虑签名与 `.app` 封装。
