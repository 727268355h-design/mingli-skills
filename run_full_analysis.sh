#!/bin/bash
# run_full_analysis.sh
# 一键运行：奇门（及其它存在的体系）排盘 → 自检 → trace → 分析 → 打包结果
# 用法: bash run_full_analysis.sh [YEAR MONTH DAY HOUR]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
QIMEN_DIR="$PROJECT_ROOT/qimen-dunjia/scripts"
OUTPUT_DIR="$QIMEN_DIR/results"
TRACE_DIR="$QIMEN_DIR/traces"

YEAR_DEFAULT=1993
MONTH_DEFAULT=10
DAY_DEFAULT=2
HOUR_DEFAULT=5

YEAR=${1:-$YEAR_DEFAULT}
MONTH=${2:-$MONTH_DEFAULT}
DAY=${3:-$DAY_DEFAULT}
HOUR=${4:-$HOUR_DEFAULT}

mkdir -p "$OUTPUT_DIR"
mkdir -p "$TRACE_DIR"

echo "════════════════════════════════════════════════════════════"
echo "🔮 全量命理流水线 — 奇门 / 八字 / 紫微 等（确定性计算）"
echo "════════════════════════════════════════════════════════════"
echo "输入时间： $YEAR-$MONTH-$DAY $HOUR:00 (本脚本默认北京时间)\n"

# 1. 创建或激活虚拟环境
if [ ! -d "$VENV_DIR" ]; then
  echo "📦 创建虚拟环境..."
  python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

# 2. 安装依赖（尽量静默）
if [ -f "requirements.txt" ]; then
  echo "📚 安装 requirements.txt..."
  pip install -r requirements.txt
else
  echo "📚 安装 sxtwl（若未安装）..."
  pip install sxtwl || true
fi

# Helper: run a qimen pipeline and capture outputs
run_qimen(){
  echo "\n🎲 运行奇门排盘: qimen.py $YEAR $MONTH $DAY $HOUR"
  cd "$QIMEN_DIR"

  # 运行排盘并保存 JSON
  python3 qimen.py "$YEAR" "$MONTH" "$DAY" "$HOUR" > "qimen_stdout.log" 2>&1 || true

  # 运行 verify
  python3 verify.py "$YEAR" "$MONTH" "$DAY" "$HOUR" > "verify_stdout.log" 2>&1 || true

  # 按照 SKILL.md 创建 trace 并记录 verify 结果
  python3 - <<PY
import json, qimen, verify, trace
Y,M,D,H = map(int, [${YEAR}, ${MONTH}, ${DAY}, ${HOUR}])
try:
    r = qimen.paipan(Y,M,D,H)
except Exception as e:
    print('paipan failed', e)
    r = {}
ok, errs, warns, checks = verify.verify_one(Y,M,D,H)
# 创建 trace
_tid = trace.create_trace(f"{Y}-{M:02d}-{D:02d} {H:02d}:00", 'User-provided full analysis', r)
trace.log_verify(_tid, ok, errs, checks)
print('TRACE_ID:', _tid)
# 存文件
with open('output.json', 'w', encoding='utf-8') as f:
    json.dump(r, f, ensure_ascii=False, indent=2)
PY

  # 移动/备份输出
  ts=$(date +%Y%m%d_%H%M%S)
  cp output.json "$OUTPUT_DIR/output_${YEAR}_${MONTH}_${DAY}_${HOUR}_${ts}.json" || true
  cp qimen_stdout.log "$OUTPUT_DIR/qimen_${ts}.log" || true
  cp verify_stdout.log "$OUTPUT_DIR/verify_${ts}.log" || true
}

# 3. 运行 qimen
if [ -d "$QIMEN_DIR" ]; then
  run_qimen
else
  echo "⚠️ 未找到奇门脚本目录: $QIMEN_DIR"
fi

# 4. 运行其他体系（如果存在命令行脚本）
# 八字（如果存在 bazi/scripts/run_bazi.py 或类似）
if [ -f "bazi/scripts/run_bazi.py" ]; then
  echo "\n🧾 运行八字脚本..."
  python3 bazi/scripts/run_bazi.py "$YEAR" "$MONTH" "$DAY" "$HOUR" || true
fi

# 紫微（如果存在入口）
if [ -f "ziwei-doushu/run_ziwei.py" ]; then
  echo "\n🔭 运行紫微斗数脚本..."
  python3 ziwei-doushu/run_ziwei.py "$YEAR" "$MONTH" "$DAY" "$HOUR" || true
fi

# 5. 汇总 traces（如果存在 analyze_traces.py）
if [ -f "$QIMEN_DIR/analyze_traces.py" ]; then
  echo "\n📊 汇总分析 traces..."
  python3 "$QIMEN_DIR/analyze_traces.py" "$TRACE_DIR" "$OUTPUT_DIR" || true
fi

# 6. 打包并显示结果目录
echo "\n════════════════════════════════════════════════════════════"
echo "✅ 全量流水线完成。输出目录： $OUTPUT_DIR"
echo " traces 目录： $TRACE_DIR"
ls -la "$OUTPUT_DIR" || true
ls -la "$TRACE_DIR" || true

echo "若需要下载 artifacts，请查看 Actions 运行结果或在仓库中直接查看 $OUTPUT_DIR 和 $TRACE_DIR"

