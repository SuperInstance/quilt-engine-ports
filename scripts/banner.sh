#!/usr/bin/env bash
# banner.sh — generate the quilt-engine-ports banner via DeepInfra sdxl-turbo.
# NOT mmx. Handles both URL and base64 responses. Skips gracefully on failure.
set -u
cd "$(dirname "$0")/.."

KEY="$(grep -oP 'DEEPINFRA_API_KEY="?\K[^"]+' ~/.bashrc | head -1)"
if [ -z "${KEY:-}" ]; then echo "NO_KEY"; exit 1; fi

PROMPT="wide horizontal banner illustration: on the left, a patchwork quilt made of glowing hexagonal fabric cells with amber thread seams; from its right edge, luminous threads split into three glowing paths leading to three miniature stylized worlds (a small pine forest diorama, a neat city grid, a canyon mesa), each world rendered as a tiny isometric scene in a glass box, dark indigo background, warm amber and teal palette, elegant technical storybook illustration, soft volumetric glow, no text"

RESP="$(curl -sS --max-time 120 \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$PROMPT"), \"width\": 1024, \"height\": 512, \"num_inference_steps\": 4, \"guidance_scale\": 0.0}" \
  https://api.deepinfra.com/v1/inference/stabilityai/sdxl-turbo 2>&1)" || { echo "CURL_FAIL: $RESP"; exit 1; }

IMG="$(printf '%s' "$RESP" | python3 -c '
import sys, json, base64, re
try:
    d = json.load(sys.stdin)
except Exception as e:
    print(f"PARSE_FAIL: {e}"); sys.exit(1)
imgs = d.get("images") or d.get("image") or (d.get("output", {}).get("images") if isinstance(d.get("output"), dict) else None)
if not imgs:
    print(f"NO_IMAGE: {str(d)[:300]}"); sys.exit(1)
src = imgs[0]
if src.startswith("http"):
    print("URL:" + src)
elif src.startswith("data:image"):
    print("B64:" + src.split(",", 1)[1])
else:
    print("B64:" + src)
')"
case "$IMG" in
  URL:*)
    URL="${IMG#URL:}"
    if curl -sS --max-time 120 -o assets/banner.png "$URL"; then echo "OK_URL $(wc -c < assets/banner.png) bytes"; else echo "DOWNLOAD_FAIL"; exit 1; fi ;;
  B64:*)
    printf '%s' "${IMG#B64:}" | base64 -d > assets/banner.png && echo "OK_B64 $(wc -c < assets/banner.png) bytes" || { echo "DECODE_FAIL"; exit 1; } ;;
  *)
    echo "GEN_FAIL: ${IMG:-empty}"; exit 1 ;;
esac
file assets/banner.png 2>/dev/null || true
