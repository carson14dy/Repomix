#!/usr/bin/env sh
# Convert Veo clips in assets/video/raw/*.mp4 to Godot-ready Ogg Theora + poster PNG:
#   assets/video/<name>.ogv          1280x720, no audio, libtheora quality 7
#   assets/video/<name>_poster.png   1280x720 first frame (shown until the video decodes)
#
# Usage:  tools/convert_backdrop.sh [clip.mp4 ...]      (default: every mp4 in assets/video/raw)
# Then:   $GODOT --headless --path . --import            (imports the poster PNG; Godot loads
#                                                           .ogv directly as VideoStreamTheora)
#
# ffmpeg: honours $FFMPEG, else the one on PATH, else the static build bundled with the
# imageio_ffmpeg Python package.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
RAW_DIR="$ROOT/assets/video/raw"
OUT_DIR="$ROOT/assets/video"
FFMPEG=${FFMPEG:-$(command -v ffmpeg || python3 -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")}
# Scale to cover 1280x720 then centre-crop, so a clip of any aspect fills the frame.
FIT="scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720,setsar=1"

if [ "$#" -gt 0 ]; then
	set -- "$@"
else
	set -- "$RAW_DIR"/*.mp4
	if [ ! -e "$1" ]; then
		echo "no clips in $RAW_DIR; run tools/veo_backdrops.py first" >&2
		exit 1
	fi
fi

mkdir -p "$OUT_DIR"
for src in "$@"; do
	name=$(basename "$src" .mp4)
	ogv="$OUT_DIR/$name.ogv"
	poster="$OUT_DIR/${name}_poster.png"
	echo "$src -> $ogv"
	"$FFMPEG" -y -hide_banner -loglevel error -i "$src" -an \
		-vf "$FIT" -c:v libtheora -q:v 7 -pix_fmt yuv420p "$ogv"
	echo "$src -> $poster"
	"$FFMPEG" -y -hide_banner -loglevel error -i "$src" -an \
		-vf "$FIT" -frames:v 1 "$poster"
done
