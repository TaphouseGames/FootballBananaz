#!/usr/bin/env bash
# Makes the raw models of crowd people with Tripo from tools/crowd_people.json,
# in three steps that are run one after the other. Run from the project root:
#
#     tools/make_person.sh concept <id> [<id> ...]   the concept picture (5 credits each)
#     tools/make_person.sh model <id> [<id> ...]     the model from it (110 credits each)
#     tools/make_person.sh uv <id> [<id> ...]        the model's UVs laid out again (20 credits each)
#
# Look at the concepts before the models are made. Everything lands in
# assets/stadium/source/tripo/people/<id>_concept, <id> and <id>_uv; put the
# path of the model.glb under <id>_uv into the person's `source`, then run
# tools/prep_people.py. The people of one call run side by side, and Tripo
# refuses more than about three at once ("concurrency limit", nothing is
# charged): give it at most three ids a call.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
step="$1"
shift
export TRIPO_CLIENT_APP="${TRIPO_CLIENT_APP:-claude}"
cd "$root/assets/stadium/source/tripo/people" || exit 1
for id in "$@"; do
    case "$step" in
    concept)
        prompt="$(python -I -c "import json, sys; c = json.load(open(sys.argv[1], encoding='utf-8')); print(c['template'].replace('{who}', c['people'][sys.argv[2]]['who']))" "$root/tools/crowd_people.json" "$id")" || exit 1
        tripo generate image-to-image ./style_players.png ../mascot/tripo-out/mascot-07cf547b/generated_image.jpeg --prompt "$prompt" -p template=t_pose --name "crowd_${id}_concept" -o "${id}_concept" --no-open --yes --json > "${id}_concept.log" 2>&1 &
        ;;
    model)
        picture="$(ls "${id}_concept"/tripo-out/*/generated_image.png | tail -n 1)" || exit 1
        tripo make "./$picture" --model tripo-p2 -p face_limit=1500 -p pbr=true --name "crowd_$id" -o "$id" --no-open --yes --json > "$id.log" 2>&1 &
        ;;
    uv)
        task="$(python -I -c "import glob, json, sys; print(json.load(open(sorted(glob.glob(sys.argv[1] + '/tripo-out/*/task.json'))[-1], encoding='utf-8'))['task_id'])" "$id")" || exit 1
        tripo mesh uv "$task" --name "crowd_${id}_uv" -o "${id}_uv" --no-open --yes --json > "${id}_uv.log" 2>&1 &
        ;;
    *)
        echo "usage: make_person.sh concept|model|uv <id> [<id> ...]"
        exit 2
        ;;
    esac
done
wait
for id in "$@"; do
    log="$id.log"
    [ "$step" = concept ] && log="${id}_concept.log"
    [ "$step" = uv ] && log="${id}_uv.log"
    echo "== $id $(grep -o '"status":"[a-z]*"\|"credits_consumed":[0-9]*\|"model_file":"[^"]*"\|"error":"[^"]*"\|"message":"[^"]*"' "$log" | tr '\n' ' ')"
done
