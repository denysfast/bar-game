#!/bin/bash
# Contact sheet: in-engine render vs Qwen portrait for every hero model -> tools/heroes/renders/sheet.png
# Pairs: renders/<base>.png with bitmaps/t4heroes/portrait_<t4>.png or portrait_base_<base>.png.
cd "$(dirname "$0")/../.."
R=tools/heroes/renders; B=bitmaps/t4heroes; T=$(mktemp -d)
for r in $R/*.png; do
	b=$(basename $r .png); [ "$b" = sheet ] && continue
	p=$B/portrait_$b.png; [ -f $p ] || p=$B/portrait_base_$b.png
	[ -f $p ] || p="xc:#400"
	magick $r -resize 192x192 \( $p -resize 192x192 \) +append -gravity south -background '#111' -fill '#ddd' \
		-splice 0x22 -pointsize 16 -annotate +0+2 "$b" $T/$b.png
done
magick montage $T/*.png -tile 6x -geometry +4+4 -background "#111" -dither None -colors 256 PNG8:$R/sheet.png
rm -rf $T; echo $R/sheet.png
