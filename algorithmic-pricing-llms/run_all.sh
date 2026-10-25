#!/usr/bin/env bash
# Launch every priority experiment (EXPERIMENT_PLAN.md) in parallel, one git worktree per branch.
#   1. competence gate: 50-round monopoly must find the monopoly price
#   2. positive-control gate: 50-round duopoly must PASS the new check
#   3. all selected runs at once: baseline (main) + chosen conditions, one run per seed
# All run folders land in this checkout's experiments_synthetic/experiments_runs/, logs in logs/.
# Usage: OPENAI_API_KEY=... MODEL_NAME=gpt-4o ./run_all.sh     (DRY_RUN=1 to only print the plan)
# Budget knobs (env vars):
#   MEMORY=20            visible history rounds (default 100); the main cost driver
#   ROUNDS=150           game length (default 300)
#   SEEDS="1 2"          seeds (default "1 2 3")
#   EXPS=comply_explicit,horizon_countdown   only these conditions (default: all 10; "none" = baseline only)
#   GATES=duopoly        which gates to run: "monopoly,duopoly" (default), "duopoly", "none"
#   NO_BASELINE=1        skip the baseline runs (e.g. already done with the same settings)
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)
REPO=$(git rev-parse --show-toplevel)
WT_ROOT="${WT_ROOT:-$(dirname "$REPO")/$(basename "$REPO")_worktrees}"

: "${MODEL_NAME:?set MODEL_NAME (e.g. gpt-4o) - batch 1 showed gpt-4o-mini fails the competence check}"
[ -n "${DRY_RUN:-}" ] || : "${OPENAI_API_KEY:?set OPENAI_API_KEY first}"
export LLM_PROVIDER=openai MODEL_NAME
ROUNDS="${ROUNDS:-300}"
SEEDS="${SEEDS:-1 2 3}"
MEMORY="${MEMORY:-100}"
EXPS="${EXPS:-all}"
GATES="${GATES:-monopoly,duopoly}"
TAG="${MODEL_NAME}_mem${MEMORY}_r${ROUNDS}"
mkdir -p logs experiments_synthetic/experiments_runs

# branch -> worktree name and the two treatment conditions (flags) to run on it
EXPERIMENTS=(
    "exp/finite-horizon|horizon_total|--horizon total"
    "exp/finite-horizon|horizon_countdown|--horizon countdown"
    "exp/compliance-line|comply_soft|--compliance soft"
    "exp/compliance-line|comply_explicit|--compliance explicit"
    "exp/rival-identity|rival_sameai|--rival sameai"
    "exp/rival-identity|rival_human|--rival human"
    "exp/monitoring-lag|lag3|--monitor-lag 3"
    "exp/monitoring-lag|lag10|--monitor-lag 10"
    "exp/noisy-demand|noise0.1|--demand-noise 0.1"
    "exp/noisy-demand|noise0.3|--demand-noise 0.3"
)

run_gate() {  # run_gate <log> <pattern> <script> <args...>
    local log=$1 pattern=$2; shift 2
    echo "== gate: $* ($MODEL_NAME) =="
    uv run python "$@" -y 2>&1 | tee "logs/$log"
    if ! grep -qE "$pattern" "logs/$log"; then
        echo "!! gate failed - nothing launched. See logs/$log"
        exit 1
    fi
}

if [ -z "${DRY_RUN:-}" ]; then
    if [[ ",$GATES," == *",monopoly,"* ]]; then
        run_gate "gate_monopoly_${TAG}.log" "Competence check.*: PASS" \
            experiments_synthetic/monopoly.py --rounds 50 --seeds 0 --memory "$MEMORY"
    fi
    if [[ ",$GATES," == *",duopoly,"* ]]; then
        run_gate "gate_duopoly_${TAG}.log" "Positive control.*: PASS" \
            experiments_synthetic/duopoly.py --rounds 50 --seeds 0 --memory "$MEMORY"
    fi
fi

# one worktree per branch; its experiments_runs/ is a symlink to ours so all results land here
worktree_dir() {
    local branch=$1 wt="$WT_ROOT/${1#exp/}"
    if [ ! -d "$wt" ]; then
        git -C "$REPO" worktree add -q "$wt" "$branch"
    fi
    local runs="$wt/algorithmic-pricing-llms/experiments_synthetic/experiments_runs"
    [ -L "$runs" ] || { rm -rf "$runs"; ln -s "$HERE/experiments_synthetic/experiments_runs" "$runs"; }
    echo "$wt/algorithmic-pricing-llms"
}

PIDS=()
launch() {  # launch <dir> <log-name> <args...>
    local dir=$1 name=$2; shift 2
    if [ -n "${DRY_RUN:-}" ]; then
        echo "[dry] ($dir) duopoly.py $* -> logs/$name.log"
        return
    fi
    (cd "$dir" && nohup uv run python experiments_synthetic/duopoly.py "$@" -y \
        > "$HERE/logs/$name.log" 2>&1) &
    PIDS+=($!)
    echo "started $name"
}

COMMON=(--rounds "$ROUNDS" --memory "$MEMORY")
if [ -z "${NO_BASELINE:-}" ]; then
    for s in $SEEDS; do
        launch "$HERE" "baseline_${TAG}_s$s" "${COMMON[@]}" --seeds "$s"
    done
fi
for e in "${EXPERIMENTS[@]}"; do
    IFS="|" read -r branch name flags <<< "$e"
    [[ "$EXPS" == all || ",$EXPS," == *",$name,"* ]] || continue
    dir=$(worktree_dir "$branch")
    for s in $SEEDS; do
        # shellcheck disable=SC2086  # $flags is intentionally split into words
        launch "$dir" "${name}_${TAG}_s$s" "${COMMON[@]}" --seeds "$s" $flags
    done
done

[ -n "${DRY_RUN:-}" ] && exit 0
echo "Launched ${#PIDS[@]} runs. Progress: ls logs/ | Results: experiments_synthetic/experiments_runs/2_agents/"
caffeinate -i &
CAF=$!
wait "${PIDS[@]}" || true
kill "$CAF" 2>/dev/null || true
echo "== all runs finished =="
grep -HE "Positive control" logs/*_"${TAG}"_s*.log || true
