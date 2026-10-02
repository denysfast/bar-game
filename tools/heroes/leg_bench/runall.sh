#!/bin/bash
# run Legion hero scenes sequentially: runall.sh helios starfall ...
S=${S:-$(cd "$(dirname "$0")" && pwd)}
cd ${W:-$(git -C "$S" rev-parse --show-toplevel)}
for n in "$@"; do
  echo "=== $n"
  W=$PWD WD=cleg SCENE_GADGET=$S/zz_cleg_scene.lua SCENE_WIDGET=$S/zz_cleg_cam.lua timeout 1000 /mnt/data/bar-bench/bench.sh $S/$n.lua $n > $S/run_$n.log 2>&1
  grep -E "\[t4heroes\]|error|Error" /mnt/data/bar-bench/out/cleg/$n/infolog.txt | grep -v "Sound\|AdvSky\|ceg_test\|FeatureDef" | head -20
done
echo ALLDONE
