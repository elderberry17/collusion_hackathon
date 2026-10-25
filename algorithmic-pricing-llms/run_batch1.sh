#!/usr/bin/env bash
# Batch 1: experiments that need no new code (see EXPERIMENT_PLAN.md).
#   1. 50-round duopoly check, foreground (must PASS: Nash < price <= 1.1x monopoly, profit > Nash)
#   2. then, in parallel: shared baseline (3 seeds), memory 0 / 10 (3 seeds each),
#      notes off (3 seeds) and a 50-round monopoly competence check = 13 runs.
# Usage: OPENAI_API_KEY=... ./run_batch1.sh        (keep the laptop plugged in, lid open)
#        SKIP_CHECK=1 ./run_batch1.sh               (if you already ran the check by hand)
set -euo pipefail
cd "$(dirname "$0")"

: "${OPENAI_API_KEY:?set OPENAI_API_KEY first}"
export LLM_PROVIDER=openai
export MODEL_NAME="${MODEL_NAME:-gpt-4o-mini}"
ROUNDS="${ROUNDS:-300}"
mkdir -p logs

if [ -z "${SKIP_CHECK:-}" ]; then
    echo "== check: 50-round duopoly with $MODEL_NAME =="
    uv run python experiments_synthetic/duopoly.py --rounds 50 --seeds 0 -y 2>&1 | tee logs/check_duopoly.log
    if ! grep -q "Positive control.*: PASS" logs/check_duopoly.log; then
        echo "!! Check did not PASS - not launching the batch. See logs/check_duopoly.log"
        exit 1
    fi
fi

PIDS=()
launch() {  # launch <log-name> <args...>
    local name=$1; shift
    nohup uv run python "$@" -y > "logs/$name.log" 2>&1 &
    PIDS+=($!)
    echo "started $name (pid $!)"
}

launch check_monopoly experiments_synthetic/monopoly.py --rounds 50 --seeds 0
for s in 1 2 3; do
    launch "baseline_s$s" experiments_synthetic/duopoly.py --rounds "$ROUNDS" --seeds "$s"
    launch "mem0_s$s"     experiments_synthetic/duopoly.py --rounds "$ROUNDS" --seeds "$s" --memory 0
    launch "mem10_s$s"    experiments_synthetic/duopoly.py --rounds "$ROUNDS" --seeds "$s" --memory 10
    launch "nonotes_s$s"  experiments_synthetic/duopoly.py --rounds "$ROUNDS" --seeds "$s" --no-notes
done

echo "All launched. Progress: tail -f logs/baseline_s1.log | Results: experiments_synthetic/experiments_runs/"
# keep the Mac awake until every run has finished
caffeinate -i &
CAF=$!
wait "${PIDS[@]}" || true
kill "$CAF" 2>/dev/null || true
echo "== batch 1 finished =="
grep -HE "Positive control|Competence check" logs/*.log || true
