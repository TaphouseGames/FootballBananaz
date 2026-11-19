#!/usr/bin/env bash
# Generates one of the stadium's modelled pieces with Tripo, in the style of
# the light towers (see docs/stadium.md, "The modelled pieces").
#
#   tools/make_stadium_part.sh concept <piece>          the concept picture (5 credits)
#   tools/make_stadium_part.sh model <piece> [faces]    the model from it, then Smart UV (about 140)
#
# <piece> is tunnel, facade_bay, roof_bay or press_box. Look at the concept
# before paying for the model. Everything lands in
# assets/stadium/source/tripo/<piece>/, which Godot does not import.
set -euo pipefail

step="$1"
piece="$2"
faces="${3:-12000}"
root="assets/stadium/source/tripo"
ref="$root/jumbotron/light_tower_ref.png"
out="$root/$piece"
style="Whole object in frame, single isolated object on a plain grey background, in exactly the stylized hand-painted game prop style, weathered concrete and grey riveted steel colours and lighting of image[1]. No people, no text, no logos."

case "$piece" in
tunnel)
	what="A new object from the same stadium as the floodlight tower in image[1]: the mouth of a spectator tunnel that sticks out of a grandstand. One plain rectangular block of weathered concrete, taller than wide and twice as deep as wide, with a flat roof. In its front face one big rectangular doorway with a pitch black inside, framed by a thick riveted grey steel portal, a small blank steel plate over the door and two small round lamps beside it. A grey steel pipe railing runs round the edge of the flat roof. Perfectly left-right symmetrical. Seen from the front and a little from above and from the side, so that the roof and one side wall show."
	;;
facade_bay)
	what="A new object from the same stadium as the floodlight tower in image[1]: one flat section of a stadium's outside wall, a little taller than wide, like one tile of a repeating wall. A thick square concrete column with riveted steel bands runs up the left edge and one up the right edge, exactly alike. Between them a weathered concrete wall: at the bottom one wide round arched gateway with a pitch black inside, above it one tall plain white blank cloth banner hanging flat on the wall between two steel brackets, above that a row of three small dark windows, and along the top a heavy grey steel cornice. Flat, shallow, perfectly left-right symmetrical. Straight-on front view."
	;;
roof_bay)
	what="A new object from the same stadium as the floodlight tower in image[1]: one section of the roof over the top of a grandstand. A wide flat corrugated grey steel roof plate, sloping up a little toward its front edge, carried by two grey steel lattice truss arms with cross bracing like the tower of image[1], which reach forward from two short lattice truss posts at the back. A row of four small round floodlights hangs under the front edge. Nothing under the roof but the posts. Perfectly left-right symmetrical. Seen from the front, a little from below and from the side, so that the trusses under the plate show."
	;;
press_box)
	what="A new object from the same stadium as the floodlight tower in image[1]: a stadium press box, the commentators' booth. One long low cabin, four times as wide as tall, of dark grey riveted steel panels, with one long row of big dark tinted glass windows across the whole front leaning forward, a flat steel roof plate with corner brackets like the lamp box of image[1], on the roof a small satellite dish, two thin antennas and a row of small round floodlights, and steel lattice brackets under the floor. Perfectly left-right symmetrical. Seen from the front and a little from above and from the side."
	;;
*)
	echo "unknown piece: $piece" >&2
	exit 1
	;;
esac

if [ "$step" = "concept" ]; then
	tripo generate image-to-image "./$ref" --prompt "$what $style" -o "$out/concept" --yes --no-open 2>&1 | tee "$out.concept.log"
elif [ "$step" = "model" ]; then
	picture="$(ls "$out"/concept/tripo-out/*/generated_image.png | head -1)"
	tripo make "./$picture" --model tripo-p2 -p face_limit="$faces" -p pbr=true -p texture_quality=detailed -o "$out/model" --yes --no-open 2>&1 | tee "$out.model.log"
	task="$(grep -o '"task_id": *"[^"]*"' "$out"/model/tripo-out/*/task.json | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
	tripo mesh uv "$task" -o "$out/uv" --yes --no-open 2>&1 | tee "$out.uv.log"
else
	echo "unknown step: $step" >&2
	exit 1
fi
