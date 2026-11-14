#!/usr/bin/env bash
# Generates a team mascot's raw model with Tripo from its prompt in
# tools/mascots.json (about 110 credits each). Run from the project root:
#
#     tools/make_mascot.sh <team> [<team> ...]
#
# The model lands in assets/stadium/source/tripo/mascot_<team>/tripo-out/.
# Put its model.glb path into the team's `source` in mascots.json, then run
# tools/prep_mascot.py on the team.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/assets/stadium/source/tripo" || exit 1
for team in "$@"; do
    prompt="$(python -I -c "import json, sys; print(json.load(open(sys.argv[1], encoding='utf-8'))[sys.argv[2]]['prompt'])" "$root/tools/mascots.json" "$team")" || exit 1
    tripo make "$prompt" --model tripo-p2 -p pbr=false --name "mascot_$team" -o "mascot_$team" --no-open --yes --json > "mascot_$team.log" 2>&1 &
done
wait
for team in "$@"; do
    echo "== $team"
    tail -n 3 "mascot_$team.log" | grep -o '"credits_consumed":[0-9]*\|"model_file":"[^"]*"\|"error":"[^"]*"'
done
