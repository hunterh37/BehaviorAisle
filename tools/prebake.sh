#!/bin/zsh
# Regenerates Prebaked/RealityHDPrebaked (bundled asset geometry, scene AO, textures). Rerun after updating RealityHD.
ROOT="$(cd "$(dirname $0)/.." && pwd)"
cd "$ROOT/../.rhd-main/RealityHD" || exit 1
~/.claude/scripts/buildq -- swift run -c release --scratch-path /tmp/ba-rhd-build realityhd prebake \
  --manifest "$ROOT/tools/prebake.json" --tier balanced --out "$ROOT/Prebaked/RealityHDPrebaked"
