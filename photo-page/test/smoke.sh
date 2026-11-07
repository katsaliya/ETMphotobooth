#!/usr/bin/env bash
# Smoke test against a running Worker (default: local `npm run dev`).
#   BASE=http://localhost:8787 KEY=local-dev-booth-key bash test/smoke.sh
set -euo pipefail
BASE="${BASE:-http://localhost:8787}"
KEY="${KEY:-local-dev-booth-key}"
DIR="$(cd "$(dirname "$0")" && pwd)"
ok() { printf '  ✓ %s\n' "$1"; }
bad() { printf '  ✗ %s\n' "$1"; exit 1; }
expect() { [ "$1" = "$2" ] && ok "$3 ($1)" || bad "$3: got $1, expected $2"; }

ID="$(python3 - <<'PY'
import time, secrets, string
def b36(n):
    s = ""
    while n: n, r = divmod(n, 36); s = "0123456789abcdefghijklmnopqrstuvwxyz"[r] + s
    return s.rjust(7, "0")
alpha = string.ascii_letters + string.digits + "-_"
print(b36(int(time.time())) + "".join(secrets.choice(alpha) for _ in range(16)))
PY
)"
echo "Session $ID"

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

expect "$(code "$BASE/p/$ID")" 200 "new session page shows 'on the way'"
curl -s "$BASE/p/$ID" | grep -q "on the way" && ok "pending text present" || bad "pending text missing"
expect "$(code -X PUT -H 'Content-Type: image/jpeg' --data-binary @"$DIR/sample.jpg" "$BASE/api/upload/$ID/strip.jpg")" 401 "upload without key rejected"
expect "$(code -X PUT -H "X-Booth-Key: wrong" -H 'Content-Type: image/jpeg' --data-binary @"$DIR/sample.jpg" "$BASE/api/upload/$ID/strip.jpg")" 401 "upload with wrong key rejected"
expect "$(code -X PUT -H "X-Booth-Key: $KEY" -H 'Content-Type: text/html' --data-binary @"$DIR/sample.jpg" "$BASE/api/upload/$ID/strip.jpg")" 415 "wrong content type rejected"
expect "$(code -X PUT -H "X-Booth-Key: $KEY" -H 'Content-Type: image/jpeg' --data-binary @"$DIR/sample.jpg" "$BASE/api/upload/$ID/other.jpg")" 400 "unknown file name rejected"
expect "$(code -X PUT -H "X-Booth-Key: $KEY" -H 'Content-Type: image/jpeg' --data-binary @"$DIR/sample.jpg" "$BASE/api/upload/short/strip.jpg")" 400 "bad session id rejected"
expect "$(code -X GET -H "X-Booth-Key: $KEY" "$BASE/api/upload/$ID/strip.jpg")" 405 "booth key cannot read"
expect "$(code -X DELETE -H "X-Booth-Key: $KEY" "$BASE/api/upload/$ID/strip.jpg")" 405 "booth key cannot delete"
expect "$(code "$BASE/api/sessions")" 404 "no session listing"

expect "$(code -X PUT -H "X-Booth-Key: $KEY" -H 'Content-Type: image/jpeg' --data-binary @"$DIR/sample.jpg" "$BASE/api/upload/$ID/strip.jpg")" 201 "strip.jpg uploaded"
curl -s "$BASE/p/$ID/status" | grep -q '"strip":true,"live":false' && ok "status: strip only" || bad "status after strip"
expect "$(code -X PUT -H "X-Booth-Key: $KEY" -H 'Content-Type: video/mp4' --data-binary @"$DIR/sample.mp4" "$BASE/api/upload/$ID/live.mp4")" 201 "live.mp4 uploaded"

curl -s "$BASE/p/$ID" | grep -q 'autoplay muted loop playsinline' && ok "page has looping inline video" || bad "video tag missing"
curl -s -D - -o /dev/null "$BASE/p/$ID" | grep -qi 'x-robots-tag: noindex' && ok "noindex header" || bad "noindex header missing"
curl -s -D - -o /dev/null "$BASE/p/$ID/live.mp4" | grep -qi 'content-type: video/mp4' && ok "video content type" || bad "video content type"
H="$(curl -s -D - -o /dev/null -H 'Range: bytes=0-1' "$BASE/p/$ID/live.mp4")"
echo "$H" | grep -q ' 206' && ok "range request → 206" || bad "range request not 206"
echo "$H" | grep -qi 'content-range: bytes 0-1/' && ok "content-range header" || bad "content-range missing"
curl -s -D - -o /dev/null "$BASE/p/$ID/strip.jpg?dl=1" | grep -qi 'content-disposition: attachment' && ok "download fallback" || bad "download fallback"
expect "$(code "$BASE/p/0000001AAAAAAAAAAAAAAAA")" 404 "very old id → expired page"
curl -s "$BASE/p/0000001AAAAAAAAAAAAAAAA" | grep -q "expired" && ok "expired text present" || bad "expired text missing"
expect "$(code "$BASE/logo.png")" 200 "logo served"
echo "All checks passed. Page: $BASE/p/$ID"
