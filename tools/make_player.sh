#!/usr/bin/env bash
# Makes the raw model of a player who is a whole character of his or her own,
# with Tripo, from tools/players.json, in four steps that are run one after
# the other. Run from the project root:
#
#     tools/make_player.sh concept <id> [<id> ...]   the concept picture (5 credits each)
#     tools/make_player.sh model <id> [<id> ...]     the model from it: smart low poly, 10k quads, PBR
#     tools/make_player.sh uv <id> [<id> ...]        its UVs laid out again (20 credits each)
#     tools/make_player.sh rig <id> [<id> ...]       an ActorCore skeleton on it
#
# Look at the concepts before the models are made. Everything lands in
# assets/player/source/tripo/<id>_concept, <id>_model, <id>_uv and <id>_rig;
# put the path of the model under <id>_rig into the player's `source`, then
# run tools/prep_player.py. The players of one call run side by side, and
# Tripo refuses more than about three at once: give it at most three ids.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
step="$1"
shift
export TRIPO_CLIENT_APP="${TRIPO_CLIENT_APP:-claude}"
cd "$root/assets/player/source/tripo" || exit 1

# The id of the newest task under a step's folder.
task_of() {
    python -I -c "import glob, json, os, sys; print(json.load(open(sorted(glob.glob(sys.argv[1] + '/tripo-out/*/task.json'), key=os.path.getmtime)[-1], encoding='utf-8'))['task_id'])" "$1"
}

for id in "$@"; do
    case "$step" in
    concept)
        prompt="$(python -I -c "import json, sys; c = json.load(open(sys.argv[1], encoding='utf-8')); p = c['players'][sys.argv[2]]; print(c['template'].replace('{who}', p['who']).replace('{refs}', p['refs']))" "$root/tools/players.json" "$id")" || exit 1
        mapfile -t images < <(python -I -c "import json, sys; [print(sys.argv[3] + '/' + i) for i in json.load(open(sys.argv[1], encoding='utf-8'))['players'][sys.argv[2]]['images']]" "$root/tools/players.json" "$id" "$root")
        tripo generate image-to-image "${images[@]}" --prompt "$prompt" -p template=t_pose --name "player_${id}_concept" -o "${id}_concept" --no-open --yes --json > "${id}_concept.log" 2>&1 &
        ;;
    model)
        picture="$(ls -t "${id}_concept"/tripo-out/*/generated_image.png | head -n 1)" || exit 1
        tripo generate image-to-model "./$picture" --model tripo-v3.1 -p smart_low_poly=true -p quad=true -p face_limit=10000 -p pbr=true -p texture_quality=detailed --name "player_${id}" -o "${id}_model" --no-open --yes --json > "${id}_model.log" 2>&1 &
        ;;
    uv)
        task="$(task_of "${id}_model")" || exit 1
        tripo mesh uv "$task" --name "player_${id}_uv" -o "${id}_uv" --no-open --yes --json > "${id}_uv.log" 2>&1 &
        ;;
    rig)
        task="$(task_of "${id}_uv")" || exit 1
        tripo anim rig "$task" --model v3.0 --rig-type biped --spec actorcore --out-format fbx --name "player_${id}_rig" -o "${id}_rig" --no-open --yes --json > "${id}_rig.log" 2>&1 &
        ;;
    *)
        echo "usage: make_player.sh concept|model|uv|rig <id> [<id> ...]"
        exit 2
        ;;
    esac
done
wait
for id in "$@"; do
    log="${id}_${step}.log"
    echo "== $id $(grep -o '"status":"[a-z]*"\|"credits_consumed":[0-9]*\|"model_file":"[^"]*"\|"error":"[^"]*"\|"message":"[^"]*"' "$log" | tr '\n' ' ')"
done
