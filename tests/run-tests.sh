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
