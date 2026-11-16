"""Stretches the plays sideways for a wider (or narrower) field.

    python tools/stretch_plays.py from=40 to=53.33 [dry]

The plays under resources/plays hold their lateral positions in yards, so they
do not follow Tuning.field_width by themselves. This rewrites them for a field
`to` yards wide, given that they were drawn for one `from` yards wide:

- A spot within KEEP yards of the ball stays where it is (the line and the
  backfield). Beyond that the spacing is stretched so that the old limit
  (half the width less a yard, see PlayController.to_world) lands on the new.
- `start` and `zone_center`: the lateral part is moved.
- `route`: its waypoints are relative to `start`, so each is moved as the spot
  on the field it stands for, and written relative to the new start.
- `zone_radius`: times to / from, to the nearest half yard, so that zones side
  by side still meet. A zone without one has the default (DEFAULT_RADIUS).

Run it ONCE on plays drawn for `from`: a second run stretches them again.
`dry` prints what would change and writes nothing.
"""

import re
import sys
from pathlib import Path

KEEP = 4.0
DEFAULT_RADIUS = 9.0
ZONE_JOB = 2
ROOT = Path(__file__).resolve().parent.parent / "resources" / "plays"


def number(value: float) -> str:
    text = f"{round(value, 1):.1f}"
    if text.endswith(".0"):
        text = text[:-2]
    return "0" if text == "-0" else text


def make_map(old_width: float, new_width: float):
    old_limit = old_width * 0.5 - 1.0
    new_limit = new_width * 0.5 - 1.0
    slope = (new_limit - KEEP) / (old_limit - KEEP)

    def stretch(y: float) -> float:
        a = abs(y)
        if a <= KEEP:
            return y
        return (KEEP + (a - KEEP) * slope) * (1.0 if y > 0.0 else -1.0)

    return stretch


def convert(text: str, stretch, ratio: float, defense: bool) -> tuple[str, list[str]]:
    notes: list[str] = []
    # Everything from one "[sub_resource" to the next blank line is one man.
    blocks = re.split(r"(\n\n)", text)
    for index, block in enumerate(blocks):
        if not block.startswith("[sub_resource"):
            continue
        label = re.search(r'^label = "(.*)"', block, re.M)
        who = label.group(1) if label else "?"
        start = re.search(r"^start = Vector2\(([^,]+), ([^)]+)\)", block, re.M)
        start_y = float(start.group(2)) if start else 0.0
        new_start_y = stretch(start_y)
        if start and number(new_start_y) != number(start_y):
            block = block.replace(start.group(0), f"start = Vector2({start.group(1)}, {number(new_start_y)})")
            notes.append(f"{who} {number(start_y)} -> {number(new_start_y)}")

        route = re.search(r"^route = PackedVector2Array\(([^)]*)\)", block, re.M)
        if route and route.group(1).strip():
            values = [float(v) for v in route.group(1).split(",")]
            for i in range(1, len(values), 2):
                values[i] = stretch(start_y + values[i]) - new_start_y
            block = block.replace(route.group(0), "route = PackedVector2Array(%s)" % ", ".join(number(v) for v in values))

        centre = re.search(r"^zone_center = Vector2\(([^,]+), ([^)]+)\)", block, re.M)
        if centre:
            block = block.replace(centre.group(0), f"zone_center = Vector2({centre.group(1)}, {number(stretch(float(centre.group(2))))})")

        job = re.search(r"^job = (\d+)", block, re.M)
        if defense and job and int(job.group(1)) == ZONE_JOB:
            radius = re.search(r"^zone_radius = (\S+)", block, re.M)
            old_radius = float(radius.group(1)) if radius else DEFAULT_RADIUS
            new_radius = number(round(old_radius * ratio * 2.0) / 2.0)
            if radius:
                block = block.replace(radius.group(0), f"zone_radius = {new_radius}")
            else:
                # Where Godot would put it: after zone_center, else after start, else last.
                anchor = job
                for name in ("zone_center", "start"):
                    found = re.search(rf"^{name} = .*$", block, re.M)
                    if found:
                        anchor = found
                        break
                block = block.replace(anchor.group(0), anchor.group(0) + f"\nzone_radius = {new_radius}")
        blocks[index] = block
    return "".join(blocks), notes


def main() -> None:
    args = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    dry = "dry" in sys.argv[1:]
    if "from" not in args or "to" not in args:
        sys.exit(__doc__)
    old_width = float(args["from"])
    new_width = float(args["to"])
    stretch = make_map(old_width, new_width)
    changed = 0
    for side in ("offense", "defense"):
        for path in sorted((ROOT / side).glob("*.tres")):
            text = path.read_text(encoding="utf-8")
            new_text, notes = convert(text, stretch, new_width / old_width, side == "defense")
            if new_text != text:
                changed += 1
                print(f"{side}/{path.name}: {'; '.join(notes)}")
                if not dry:
                    path.write_text(new_text, encoding="utf-8", newline="\n")
    print(f"{changed} plays {'would be ' if dry else ''}changed")


if __name__ == "__main__":
    main()
