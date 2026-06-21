#!/bin/bash
# 编译 qrscan 并安装二进制/胶水脚本与快速操作（全部装到用户目录，无需 sudo）
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$HOME/Library/Application Support/mac-qr-scanner"
SERVICES="$HOME/Library/Services"
WORKFLOW="识别二维码.workflow"

echo "==> 编译 qrscan"
swiftc -O "$HERE/Sources/qrscan/main.swift" -o "$HERE/qrscan"

echo "==> 安装到 $APPDIR"
mkdir -p "$APPDIR"
cp "$HERE/qrscan" "$APPDIR/qrscan"
cp "$HERE/scripts/qr-quick-action.sh" "$APPDIR/qr-quick-action.sh"
chmod +x "$APPDIR/qr-quick-action.sh" "$APPDIR/qrscan"

echo "==> 安装快速操作到 $SERVICES"
mkdir -p "$SERVICES"
rm -rf "$SERVICES/$WORKFLOW"
cp -R "$HERE/automator/$WORKFLOW" "$SERVICES/"

echo "==> 完成。若菜单未出现，到 系统设置 > 键盘 > 键盘快捷键 > 服务 中启用「识别二维码」，"
echo "    然后在 Finder 右击图片 > 快速操作 > 识别二维码。"
