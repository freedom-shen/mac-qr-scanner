# mac-qr-scanner

macOS 上的一个极简工具：在 Finder 里**右击图片 → 快速操作 →「识别二维码」**，自动把二维码内容复制到剪贴板。

## 功能

- 通过 Finder「快速操作」(Quick Action) 入口，右击图片即可识别
- 使用 Apple 官方 **Vision** 框架（`VNDetectBarcodesRequest`）识别，零外部依赖
- 识别结果：
  - **1 个二维码** → 静默复制到剪贴板 + 系统通知
  - **多个二维码** → 弹出选单让你挑选要复制的内容
  - **未识别到** → 通知提示「未发现二维码」

## 架构

- `qrscan`（`Sources/qrscan/main.swift`）—— 极小的 Swift 命令行工具，单一职责：图片路径 → 识别 → 按行输出去重后的二维码内容
- `scripts/qr-quick-action.sh` —— 胶水层：调用 `qrscan`，再用 `pbcopy` 复制、`osascript` 弹选单/通知
- `automator/识别二维码.workflow` —— Automator 快速操作，作为 Finder 右键入口

## 安装

```bash
git clone https://github.com/freedom-shen/mac-qr-scanner.git
cd mac-qr-scanner
./install.sh
```

首次安装后若右键菜单未出现，到 系统设置 > 键盘 > 键盘快捷键 > 服务 中启用「识别二维码」。

## 使用

在 Finder 右击一张或多张图片 → 快速操作 → 识别二维码：

- 1 个二维码 → 内容直接复制到剪贴板（通知提示）
- 多个 → 弹选单挑一个复制
- 没识别到 → 通知「未发现二维码」

## 开发

```bash
make build   # 编译 qrscan
make test    # 跑 qrscan 端到端测试 + 胶水脚本行为测试
make install # = ./install.sh
```

要求 macOS Ventura 及以上、Swift 工具链（Xcode 命令行工具）。
