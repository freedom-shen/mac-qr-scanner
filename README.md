# mac-qr-scanner

macOS 上的一个极简工具：在 Finder 里**右击图片 → 快速操作 →「识别二维码」**，自动把二维码内容复制到剪贴板。

## 功能

- 通过 Finder「快速操作」(Quick Action) 入口，右击图片即可识别
- 使用 Apple 官方 **Vision** 框架（`VNDetectBarcodesRequest`）识别，零外部依赖
- 识别结果：
  - **1 个二维码** → 静默复制到剪贴板 + 系统通知
  - **多个二维码** → 弹出选单让你挑选要复制的内容
  - **未识别到** → 通知提示「未发现二维码」

## 架构（计划中）

- `qrscan` —— 极小的 Swift 命令行工具，单一职责：图片路径 → 识别 → 按行输出二维码内容
- Automator 快速操作 —— 胶水层：调用 `qrscan`，再用 `pbcopy` 复制、`osascript` 弹选单/通知

## 状态

🚧 设计与开发中。
