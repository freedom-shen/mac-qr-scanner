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
