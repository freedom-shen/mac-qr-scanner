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
