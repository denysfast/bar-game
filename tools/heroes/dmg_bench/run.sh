#!/bin/bash
# usage: run.sh <worktree> <tag> <prefix> [only-hero,...]   -> /mnt/data/bar-bench/hdmg/<tag>/<prefix>/infolog.txt
set -u
B=/mnt/data/bar-bench; W=$1; TAG=$2; P=$3; ONLY=${4:-}
D=$B/hdmg/$TAG/$P
mkdir -p $D/games $D/maps
rsync -a --delete --exclude .git "$W"/ $D/game/
cp "$(dirname "$(readlink -f "$0")")/zz_herodmg.lua" $D/game/luarules/gadgets/
ONLYLUA="nil"
if [ -n "$ONLY" ]; then ONLYLUA="{"; for n in ${ONLY//,/ }; do ONLYLUA="$ONLYLUA $n = true,"; done; ONLYLUA="$ONLYLUA }"; fi
cat > $D/game/luarules/configs/zz_herodmg_cfg.lua <<LUA
return { prefix = "$P", levels = { 50, 75, 99 }, window = ${WINDOW:-750}, target = "cort4hellwalker", only = $ONLYLUA, weapon = ${WPN:-false} }
LUA
ln -sfn $D/game $D/games/Beyond-All-Reason.sdd
[ -e $D/maps/comet_catcher_redux.sd7 ] || ln -s $B/wd/maps/comet_catcher_redux.sd7 $D/maps/
cp $B/hl/springsettings.cfg $D/
[ -d $D/cache ] || cp -a $B/hl/cache $D/cache
cp $B/start.txt $D/start.txt
cd $D
nice -n 10 timeout ${TIMEOUT:-5400} $B/engine/spring-headless --isolation --write-dir $D $D/start.txt > $D/stdout.log 2>&1
echo "rc=$?"
grep -c "RESULT" $D/infolog.txt
