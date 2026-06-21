# mac-qr-scanner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Finder 右击图片，通过「快速操作 → 识别二维码」把二维码内容复制到剪贴板，并给系统通知。

**Architecture:** 两层职责隔离 —— (1) 纯识别 CLI `qrscan`（Swift + Vision 框架，图片路径进、二维码内容按行出）；(2) Automator 快速操作调用胶水脚本 `qr-quick-action.sh` 做 UX 编排（`pbcopy` 复制、`osascript` 通知与多码选单）。

**Tech Stack:** Swift 6.2（`swiftc` 单文件编译，无 Xcode 工程）、Apple Vision (`VNDetectBarcodesRequest`)、CoreImage (`CIQRCodeGenerator`，仅测试用)、Bash、Automator Quick Action、`osascript` / `pbcopy`。

**测试说明：** 无外部依赖。测试样图在测试运行时用 CoreImage 的 `CIQRCodeGenerator` 即时生成（已知内容 → 生成 PNG → 喂给 `qrscan` → 断言输出），生成图不入库（`.gitignore` 忽略 `tests/fixtures/`）。

**目标系统：** macOS Ventura 及以上（开发机为 macOS 26.3 / Swift 6.2）。

---

## File Structure

- `Sources/qrscan/main.swift` —— 纯识别 CLI：图片路径参数 → stdout 按行输出去重后的二维码内容；退出码 0=有/1=无/2=参数错。
- `tests/genfixtures.swift` —— 测试夹具生成器：用 CIQRCodeGenerator 生成已知内容的 QR PNG、空白无码图、双码合成图。
- `tests/run-tests.sh` —— `qrscan` 的端到端断言（生成夹具 → 跑 qrscan → 比对 stdout 与退出码）。
- `tests/test-glue.sh` —— `qr-quick-action.sh` 的行为测试（用假的 qrscan/pbcopy/osascript 注入 PATH，断言 0/1/多/取消 四条路径）。
- `scripts/qr-quick-action.sh` —— 胶水层：调 `qrscan`，按结果数编排复制/选单/通知。
- `automator/识别二维码.workflow/` —— 受版本控制的 Automator 快速操作（GUI 创建一次后导出入库）。
- `install.sh` —— 编译 qrscan + 安装二进制/脚本到 `~/Library/Application Support/mac-qr-scanner/` + 安装 workflow 到 `~/Library/Services/`。
- `Makefile` —— `build` / `test` / `install` 目标。

---

## Task 1: `qrscan` 识别 CLI（TDD：先写测试夹具与断言）

**Files:**
- Create: `tests/genfixtures.swift`
- Create: `tests/run-tests.sh`
- Create: `Makefile`
- Test: `tests/run-tests.sh`

- [ ] **Step 1: 写夹具生成器 `tests/genfixtures.swift`**

```swift
import Foundation
import CoreImage
import AppKit

// 用 CIQRCodeGenerator 生成一张包含 payload 的二维码 CIImage（放大 10 倍便于识别）
func qrImage(_ payload: String) -> CIImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(payload.data(using: .utf8), forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    return filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
}

func writePNG(_ image: CIImage, to path: String) {
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(image, from: image.extent) else {
        fatalError("createCGImage failed for \(path)")
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "tests/fixtures"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 单码：URL / 纯文本 / 中文
writePNG(qrImage("https://example.com"), to: "\(outDir)/url.png")
writePNG(qrImage("hello world"), to: "\(outDir)/text.png")
writePNG(qrImage("你好二维码"), to: "\(outDir)/chinese.png")

// 无码：纯白图
let blank = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
writePNG(blank, to: "\(outDir)/blank.png")

// 双码：把两张二维码横向拼到一张白底图上
let a = qrImage("https://first.example")
let b = qrImage("https://second.example")
    .transformed(by: CGAffineTransform(translationX: a.extent.width + 40, y: 0))
let combined = b.composited(over: a)
let bg = CIImage(color: .white).cropped(to: combined.extent.insetBy(dx: -20, dy: -20))
writePNG(combined.composited(over: bg), to: "\(outDir)/multi.png")

print("fixtures written to \(outDir)")
```

- [ ] **Step 2: 写端到端断言脚本 `tests/run-tests.sh`**

```bash
#!/bin/bash
# qrscan 的端到端测试：生成夹具 -> 跑 qrscan -> 比对输出与退出码
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QRSCAN="$ROOT/qrscan"
FIX="$ROOT/tests/fixtures"

fail=0
check() {
  local name="$1" expected_out="$2" expected_code="$3"; shift 3
  local out code
  out="$("$QRSCAN" "$@" 2>/dev/null)"; code=$?
  if [[ "$out" == "$expected_out" && "$code" == "$expected_code" ]]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name"
    echo "       expected(code=$expected_code): [$expected_out]"
    echo "       actual  (code=$code): [$out]"
    fail=1
  fi
}

echo "生成测试夹具..."
swift "$ROOT/tests/genfixtures.swift" "$FIX" >/dev/null

check "url"     "https://example.com" 0 "$FIX/url.png"
check "text"    "hello world"         0 "$FIX/text.png"
check "chinese" "你好二维码"           0 "$FIX/chinese.png"
check "blank"   ""                    1 "$FIX/blank.png"

# 多码：Vision 返回顺序不保证，按行排序后再比对（顺序无关）
multi_out="$("$QRSCAN" "$FIX/multi.png" 2>/dev/null | sort)"; multi_code=$?
multi_expected="$(printf 'https://first.example\nhttps://second.example' | sort)"
if [[ "$multi_out" == "$multi_expected" && "$multi_code" == "0" ]]; then
  echo "ok   - multi"
else
  echo "FAIL - multi : 期望[$multi_expected] 实际[$multi_out] code=$multi_code"
  fail=1
fi

exit $fail
```

- [ ] **Step 3: 写 `Makefile`**

```makefile
.PHONY: build test install clean

build:
	swiftc -O Sources/qrscan/main.swift -o qrscan

test: build
	bash tests/run-tests.sh
	bash tests/test-glue.sh

install:
	bash install.sh

clean:
	rm -f qrscan
	rm -rf tests/fixtures
```

- [ ] **Step 4: 运行测试，确认失败（qrscan 尚不存在 / build 失败）**

Run: `make test`
Expected: `make build` 因 `Sources/qrscan/main.swift` 不存在而失败（或 run-tests 报 qrscan 缺失）。这是预期的红灯。

- [ ] **Step 5: 实现 `Sources/qrscan/main.swift`**

```swift
import Foundation
import Vision
import ImageIO

func warn(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// 识别单张图片里的所有 QR 内容；读图失败则告警并返回空
func detectQRCodes(in path: String) -> [String] {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        warn("warning: 无法读取图片: \(path)")
        return []
    }
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        warn("warning: 识别失败 \(path): \(error)")
        return []
    }
    let observations = request.results ?? []
    return observations.compactMap { $0.payloadStringValue }
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    warn("usage: qrscan <image> [<image>...]")
    exit(2)
}

var seen = Set<String>()
var ordered: [String] = []
for path in args {
    for payload in detectQRCodes(in: path) where seen.insert(payload).inserted {
        ordered.append(payload)
    }
}

for line in ordered {
    print(line)
}
exit(ordered.isEmpty ? 1 : 0)
```

- [ ] **Step 6: 运行测试，确认 qrscan 相关用例通过**

Run: `make build && bash tests/run-tests.sh`
Expected: 5 行全部 `ok`，脚本退出码 0。（`make test` 此刻还会因 `tests/test-glue.sh` 不存在而报错，属正常，下一个 Task 处理。）

- [ ] **Step 7: 更新 `.gitignore` 忽略生成的夹具**

在 `.gitignore` 末尾追加：

```
# 测试时生成的夹具
tests/fixtures/
```

- [ ] **Step 8: 提交**

```bash
git add Sources/qrscan/main.swift tests/genfixtures.swift tests/run-tests.sh Makefile .gitignore
git commit -m "feat: 实现 qrscan 识别 CLI 与端到端测试

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `qr-quick-action.sh` 胶水脚本（TDD：注入假命令测行为）

**Files:**
- Create: `scripts/qr-quick-action.sh`
- Test: `tests/test-glue.sh`

胶水脚本通过两个钩子保证可测试：`QRSCAN_BIN` 环境变量可覆盖识别器路径；`pbcopy` / `osascript` 走 PATH 解析，测试时用假命令前置到 PATH。

- [ ] **Step 1: 写行为测试 `tests/test-glue.sh`**

```bash
#!/bin/bash
# qr-quick-action.sh 行为测试：用假 qrscan/pbcopy/osascript 验证 0/1/多/取消 路径
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/qr-quick-action.sh"
fail=0

run_case() {
  local name="$1" qr_output="$2" osa_choice="$3" expect_clip="$4"
  local tmp; tmp="$(mktemp -d)"

  # 假 qrscan：打印预设内容，按是否为空决定退出码（0 有/1 无）
  cat > "$tmp/qrscan" <<EOF
#!/bin/bash
out=\$(cat <<'PAYLOAD'
$qr_output
PAYLOAD
)
if [[ -z "\$out" ]]; then exit 1; fi
printf '%s\n' "\$out"
exit 0
EOF
  chmod +x "$tmp/qrscan"

  # 假 pbcopy：把 stdin 写到文件
  cat > "$tmp/pbcopy" <<EOF
#!/bin/bash
cat > "$tmp/clip.txt"
EOF
  chmod +x "$tmp/pbcopy"

  # 假 osascript：多码选单返回预设选择；其余调用（通知）忽略
  cat > "$tmp/osascript" <<EOF
#!/bin/bash
printf '%s' "$osa_choice"
exit 0
EOF
  chmod +x "$tmp/osascript"

  : > "$tmp/clip.txt"
  QRSCAN_BIN="$tmp/qrscan" PATH="$tmp:$PATH" bash "$SCRIPT" dummy.png >/dev/null 2>&1

  local got; got="$(cat "$tmp/clip.txt")"
  if [[ "$got" == "$expect_clip" ]]; then
    echo "ok   - $name"
  else
    echo "FAIL - $name : 剪贴板期望[$expect_clip] 实际[$got]"
    fail=1
  fi
  rm -rf "$tmp"
}

# 无码：剪贴板应保持为空
run_case "none"  ""                            ""                  ""
# 单码：内容应进剪贴板（选单不触发，osa_choice 无所谓）
run_case "single" "https://only.example"       ""                  "https://only.example"
# 多码：osascript 返回所选项，该项应进剪贴板
run_case "multi"  "$(printf 'A-line\nB-line')"  "B-line"            "B-line"
# 多码取消：剪贴板应保持为空
run_case "cancel" "$(printf 'A-line\nB-line')"  "___CANCELLED___"   ""

exit $fail
```

- [ ] **Step 2: 运行测试，确认失败（脚本不存在）**

Run: `bash tests/test-glue.sh`
Expected: 4 个用例均 FAIL（`qr-quick-action.sh` 不存在，剪贴板始终为空，single/multi 用例失败），退出码 1。

- [ ] **Step 3: 实现 `scripts/qr-quick-action.sh`**

```bash
#!/bin/bash
# 「识别二维码」快速操作胶水脚本：调 qrscan，按结果数复制/选单/通知。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
QRSCAN="${QRSCAN_BIN:-$HERE/qrscan}"

notify() {
  osascript -e "display notification \"$1\" with title \"识别二维码\"" >/dev/null 2>&1
}

copy_and_notify() {
  local content="$1"
  printf '%s' "$content" | pbcopy
  notify "已复制：${content:0:100}"
}

if [[ ! -x "$QRSCAN" ]]; then
  notify "qrscan 未安装，请运行 install.sh"
  exit 1
fi

payloads="$("$QRSCAN" "$@")"

if [[ -z "$payloads" ]]; then
  notify "未发现二维码"
  exit 0
fi

count="$(printf '%s\n' "$payloads" | grep -c '.')"

if [[ "$count" -eq 1 ]]; then
  copy_and_notify "$payloads"
  exit 0
fi

# 多码：写临时文件交给 osascript（避免内容中的引号注入），弹选单
tmp="$(mktemp)"
printf '%s' "$payloads" > "$tmp"
chosen="$(osascript - "$tmp" <<'APPLESCRIPT'
on run argv
  set f to item 1 of argv
  set txt to read POSIX file f as «class utf8»
  set theList to paragraphs of txt
  set theChoice to choose from list theList with title "识别二维码" with prompt "选择要复制的内容："
  if theChoice is false then
    return "___CANCELLED___"
  else
    return item 1 of theChoice
  end if
end run
APPLESCRIPT
)"
rm -f "$tmp"

if [[ "$chosen" == "___CANCELLED___" || -z "$chosen" ]]; then
  exit 0
fi
copy_and_notify "$chosen"
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `chmod +x scripts/qr-quick-action.sh && bash tests/test-glue.sh`
Expected: 4 个用例全部 `ok`，退出码 0。

- [ ] **Step 5: 跑完整 `make test` 确认两套测试都绿**

Run: `make test`
Expected: run-tests.sh 5 个 ok + test-glue.sh 4 个 ok，整体退出码 0。

- [ ] **Step 6: 提交**

```bash
git add scripts/qr-quick-action.sh tests/test-glue.sh
git commit -m "feat: 实现胶水脚本与行为测试（0/1/多/取消）

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Automator 快速操作（创建一次并导出入库）

macOS 的快速操作由 Automator 创作。先用 GUI 按精确设置创建，再导出到仓库使其可复现；此后安装只是拷贝该 `.workflow` 包。

**Files:**
- Create: `automator/识别二维码.workflow/`（通过 Automator 导出得到的包，含 `Contents/Info.plist` 与 `Contents/document.wflow`）

- [ ] **Step 1: 在 Automator 创建快速操作**

手动操作（精确设置）：
1. 打开「自动操作 / Automator」→ 新建文稿 → 选「快速操作 (Quick Action)」。
2. 顶部设置：「工作流程收到当前的」选 **图像文件**；「位于」选 **访达 (Finder)**。
3. 左侧动作库搜索「运行 Shell 脚本」，拖到右侧工作流区域。
4. 该动作设置：Shell 选 `/bin/bash`；「传递输入」选 **作为参数**。
5. 脚本框内容填**恰好这一行**：
   ```bash
   exec "$HOME/Library/Application Support/mac-qr-scanner/qr-quick-action.sh" "$@"
   ```
6. `⌘S` 保存，名称填 **识别二维码**。（保存后系统会写入 `~/Library/Services/识别二维码.workflow`。）

- [ ] **Step 2: 把保存的 workflow 导入仓库**

Run:
```bash
mkdir -p automator
cp -R "$HOME/Library/Services/识别二维码.workflow" automator/
```
Expected: `automator/识别二维码.workflow/Contents/document.wflow` 存在。

- [ ] **Step 3: 校验 workflow 关键设置已落盘**

Run:
```bash
/usr/libexec/PlistBuddy -c Print "automator/识别二维码.workflow/Contents/Info.plist" | grep -i -E "public.image|finder|NSMenuItem|识别二维码"
```
Expected: 能看到服务菜单名「识别二维码」、接收类型 `public.image` 与 Finder 上下文相关键值。

- [ ] **Step 4: 提交**

```bash
git add automator
git commit -m "feat: 加入 Automator「识别二维码」快速操作

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `install.sh` 安装脚本

**Files:**
- Create: `install.sh`

- [ ] **Step 1: 写 `install.sh`**

```bash
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
```

- [ ] **Step 2: 运行安装并验证落盘**

Run:
```bash
bash install.sh
test -x "$HOME/Library/Application Support/mac-qr-scanner/qrscan" && \
test -x "$HOME/Library/Application Support/mac-qr-scanner/qr-quick-action.sh" && \
test -d "$HOME/Library/Services/识别二维码.workflow" && echo "INSTALL OK"
```
Expected: 末尾打印 `INSTALL OK`。

- [ ] **Step 3: 手动端到端验证（Finder）**

1. 在 Finder 右击一张含**单个**二维码的图片 → 快速操作 → 识别二维码 → 应弹通知「已复制：…」，`⌘V` 可粘出内容。
2. 右击含**多个**二维码的图片 → 应弹选单，选一项后通知并可粘出。
3. 右击**无**二维码的图片 → 应弹通知「未发现二维码」，剪贴板不变。

- [ ] **Step 4: 提交**

```bash
git add install.sh
git commit -m "feat: 加入 install.sh 安装脚本

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: README 收尾与推送

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 更新 README 的「状态」与「安装/使用」**

把 `README.md` 的「## 状态」一节替换为：

```markdown
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
```

- [ ] **Step 2: 提交并推送**

```bash
git add README.md
git commit -m "docs: 补充安装/使用/开发说明

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push origin main
```

---

## 验证（整体）

- `make test` 全绿：`qrscan` 对 url/text/中文/无码/多码 五类输入输出与退出码正确；胶水脚本 0/1/多/取消 四条路径正确。
- `bash install.sh` 后三处落盘文件就位（`INSTALL OK`）。
- Finder 右击图片端到端：单码静默复制+通知、多码弹选单、无码提示，三条均符合预期。
