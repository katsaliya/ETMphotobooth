/**
 * Emporium Thai Market photobooth — guest photo pages.
 *
 * Routes
 *   PUT /api/upload/<id>/strip.jpg   booth only (X-Booth-Key), image/jpeg, ≤ 10 MB
 *   PUT /api/upload/<id>/live.mp4    booth only (X-Booth-Key), video/mp4,  ≤ 50 MB
 *   GET /p/<id>                       the guest's photo page
 *   GET /p/<id>/status                { strip, live, expired } for the page's polling
 *   GET /p/<id>/strip.jpg|live.mp4    media, with Range support (iPhone video needs it)
 *   /logo.png etc.                    static files from ./public
 *
 * There is deliberately no list / delete / admin route. The booth key can
 * only write the two allowed files; reading is by unguessable link only.
 * Storage: R2 `sessions/<id>/strip.jpg` and `sessions/<id>/live.mp4`.
 * Deletion: an R2 lifecycle rule removes `sessions/` objects after 3 days
 * (keep RETENTION_DAYS, the rule and the booth's UploadQueue.maxAge in sync).
 */

export interface Env {
  PHOTOS: R2Bucket;
  BOOTH_KEY: string;
  ASSETS: Fetcher;
}

const FILES = {
  "strip.jpg": { type: "image/jpeg", max: 10 * 1024 * 1024, download: "emporium-photobooth.jpg" },
  "live.mp4": { type: "video/mp4", max: 50 * 1024 * 1024, download: "emporium-photobooth-live.mp4" },
} as const;
type FileName = keyof typeof FILES;

const RETENTION_DAYS = 3;
/** How long a session with no files yet still shows "on the way". */
const PENDING_WINDOW_MS = 24 * 60 * 60 * 1000;
/** The booth retries uploads for up to 3 days (offline queue); no point accepting older ones. */
const UPLOAD_WINDOW_MS = RETENTION_DAYS * 24 * 60 * 60 * 1000;
const CLOCK_SKEW_MS = 60 * 60 * 1000;

const ORDER_URL = "https://emporium-thai-market.square.site";

/**
 * Session IDs: 7 base36 chars of the creation time (unix seconds) followed by
 * 16+ random URL-safe chars. The random part makes links unguessable; the
 * time prefix lets the page tell "still uploading" from "expired" without a
 * database.
 */
const ID_PATTERN = /^[0-9a-z]{7}[A-Za-z0-9_-]{16,57}$/;

function sessionCreatedAt(id: string): number | null {
  if (!ID_PATTERN.test(id)) return null;
  const seconds = parseInt(id.slice(0, 7), 36);
  return Number.isFinite(seconds) ? seconds * 1000 : null;
}

const SECURITY_HEADERS: Record<string, string> = {
  "X-Robots-Tag": "noindex, nofollow, noarchive",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const parts = url.pathname.split("/").filter(Boolean);

    try {
      if (parts[0] === "api" && parts[1] === "upload" && parts.length === 4) {
        return await handleUpload(request, env, parts[2], parts[3]);
      }
      if (parts[0] === "p" && parts.length === 2 && isRead(request)) {
        return await handlePage(env, parts[1]);
      }
      if (parts[0] === "p" && parts.length === 3 && parts[2] === "status" && isRead(request)) {
        return await handleStatus(env, parts[1]);
      }
      if (parts[0] === "p" && parts.length === 3 && parts[2] in FILES && isRead(request)) {
        return await handleMedia(request, env, parts[1], parts[2] as FileName, url.searchParams.has("dl"));
      }
      if (parts.length === 0) {
        return html(expiredPage("Scan the code at the booth to get your photos."), 404);
      }
      // Static files (logo). Anything else is a plain 404.
      const asset = await env.ASSETS.fetch(request);
      if (asset.status !== 404) return withHeaders(asset, SECURITY_HEADERS);
      return text("Not found", 404);
    } catch (err) {
      console.error(err);
      return text("Something went wrong", 500);
    }
  },
} satisfies ExportedHandler<Env>;

function isRead(request: Request): boolean {
  return request.method === "GET" || request.method === "HEAD";
}

// MARK: - Upload (booth only)

async function handleUpload(request: Request, env: Env, id: string, file: string): Promise<Response> {
  if (request.method !== "PUT") return text("Method not allowed", 405, { Allow: "PUT" });
  if (!(await keyMatches(request.headers.get("X-Booth-Key"), env.BOOTH_KEY))) {
    return text("Unauthorized", 401);
  }

  const created = sessionCreatedAt(id);
  const now = Date.now();
  if (created === null || created > now + CLOCK_SKEW_MS || now - created > UPLOAD_WINDOW_MS) {
    return text("Bad session id", 400);
  }
  if (!(file in FILES)) return text("Unknown file", 400);
  const spec = FILES[file as FileName];

  const contentType = (request.headers.get("Content-Type") ?? "").split(";")[0].trim().toLowerCase();
  if (contentType !== spec.type) return text(`Expected ${spec.type}`, 415);

  const length = Number(request.headers.get("Content-Length"));
  if (!Number.isFinite(length) || length <= 0) return text("Content-Length required", 411);
  if (length > spec.max) return text("File too large", 413);
  if (!request.body) return text("Empty body", 400);

  await env.PHOTOS.put(`sessions/${id}/${file}`, request.body, {
    httpMetadata: { contentType: spec.type },
  });
  return json({ ok: true }, 201);
}

/** Constant-time compare of the booth key. */
async function keyMatches(given: string | null, expected: string | undefined): Promise<boolean> {
  if (!given || !expected) return false;
  const enc = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(given)),
    crypto.subtle.digest("SHA-256", enc.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

// MARK: - Guest page

type SessionState =
  | { kind: "expired" }
  | { kind: "pending" }
  | { kind: "ready"; strip: boolean; live: boolean };

async function sessionState(env: Env, id: string): Promise<SessionState> {
  const created = sessionCreatedAt(id);
  const now = Date.now();
  if (created === null || created > now + CLOCK_SKEW_MS) return { kind: "expired" };
  if (now - created > RETENTION_DAYS * 24 * 60 * 60 * 1000) return { kind: "expired" };

  const [strip, live] = await Promise.all([
    env.PHOTOS.head(`sessions/${id}/strip.jpg`),
    env.PHOTOS.head(`sessions/${id}/live.mp4`),
  ]);
  if (strip || live) return { kind: "ready", strip: !!strip, live: !!live };
  if (now - created < PENDING_WINDOW_MS) return { kind: "pending" };
  return { kind: "expired" };
}

async function handleStatus(env: Env, id: string): Promise<Response> {
  const state = await sessionState(env, id);
  return json({
    expired: state.kind === "expired",
    strip: state.kind === "ready" && state.strip,
    live: state.kind === "ready" && state.live,
  });
}

async function handlePage(env: Env, id: string): Promise<Response> {
  const state = await sessionState(env, id);
  if (state.kind === "expired") return html(expiredPage(), 404);
  return html(photoPage(id, state.kind === "ready" ? state : { strip: false, live: false }));
}

// MARK: - Media (with Range requests)

async function handleMedia(request: Request, env: Env, id: string, file: FileName, download: boolean): Promise<Response> {
  const state = await sessionState(env, id);
  if (state.kind === "expired") return text("This link expired", 404);

  const key = `sessions/${id}/${file}`;
  const spec = FILES[file];
  const rangeHeader = request.headers.get("Range");

  const object = await env.PHOTOS.get(key, rangeHeader ? { range: request.headers } : {});
  if (!object) return text("Not found", 404);

  const headers = new Headers(SECURITY_HEADERS);
  headers.set("Content-Type", spec.type);
  headers.set("Accept-Ranges", "bytes");
  headers.set("ETag", object.httpEtag);
  headers.set("Cache-Control", "private, max-age=3600");
  headers.set(
    "Content-Disposition",
    `${download ? "attachment" : "inline"}; filename="${spec.download}"`
  );

  const size = object.size;
  let status = 200;
  let length = size;
  const range = (object as R2ObjectBody & { range?: R2Range }).range;
  if (rangeHeader && range) {
    let start = 0;
    let end = size - 1;
    if ("suffix" in range && range.suffix !== undefined) {
      start = Math.max(size - range.suffix, 0);
    } else {
      start = ("offset" in range && range.offset) || 0;
      end = "length" in range && range.length !== undefined ? start + range.length - 1 : size - 1;
    }
    end = Math.min(end, size - 1);
    length = end - start + 1;
    status = 206;
    headers.set("Content-Range", `bytes ${start}-${end}/${size}`);
  }
  headers.set("Content-Length", String(length));

  return new Response(request.method === "HEAD" ? null : object.body, { status, headers });
}

// MARK: - HTML

function photoPage(id: string, files: { strip: boolean; live: boolean }): string {
  const base = `/p/${encodeURIComponent(id)}`;
  const ready = files.strip && files.live;
  const body = ready
    ? `
      <video id="live" src="${base}/live.mp4" autoplay muted loop playsinline preload="auto"
             aria-label="Your live photobooth strip"></video>
      <div class="actions">
        <button class="primary" data-save="live.mp4">Save video</button>
        <a class="fallback" href="${base}/live.mp4?dl=1" download>Download video</a>
      </div>

      <img id="strip" src="${base}/strip.jpg" alt="Your photobooth strip in color">
      <div class="actions">
        <button class="primary" data-save="strip.jpg">Save photo</button>
        <a class="fallback" href="${base}/strip.jpg?dl=1" download>Download photo</a>
      </div>`
    : `
      <div class="pending" role="status" aria-live="polite">
        <div class="spinner" aria-hidden="true"></div>
        <p class="lead">Your photos are on the way…</p>
        <p class="small">Keep this page open. It updates by itself.</p>
      </div>`;

  return layout(
    "Your photobooth photos",
    `
    <h1>Your photos in color &amp; <em>live.</em></h1>
    ${ready ? `<p class="sub">Save the video and the photo, then tag us <strong>@emporiumthaimarket</strong>.</p>` : ""}
    ${body}
    <p class="tag">tag us <strong>@emporiumthaimarket</strong></p>
    <p class="small"><a href="${ORDER_URL}" rel="noopener">Order online</a></p>
    <p class="small muted">Photos are deleted after ${RETENTION_DAYS} days.</p>`,
    ready ? saveScript(base) : pollScript(base)
  );
}

function expiredPage(message = `Photos are deleted after ${RETENTION_DAYS} days, so this one is gone. Come back and take some new ones!`): string {
  return layout(
    "This link expired",
    `
    <h1>This link <em>expired.</em></h1>
    <p class="lead">${message}</p>
    <p class="tag">tag us <strong>@emporiumthaimarket</strong></p>
    <p class="small"><a href="${ORDER_URL}" rel="noopener">Order online</a></p>`,
    ""
  );
}

function layout(title: string, content: string, script: string): string {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow, noarchive">
<meta name="referrer" content="no-referrer">
<meta name="theme-color" content="#428EA8">
<title>${title} · Emporium Thai Market</title>
<style>
  :root { --teal: #428EA8; --deep: #2A526B; --ink: #111; --white: #fff; }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--teal); color: var(--white); }
  body {
    font: 500 17px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    padding: max(20px, env(safe-area-inset-top)) 16px max(32px, env(safe-area-inset-bottom));
    display: flex; flex-direction: column; align-items: center;
  }
  main { width: 100%; max-width: 480px; display: flex; flex-direction: column; align-items: center; text-align: center; }
  .brand { display: flex; align-items: center; gap: 12px; margin-bottom: 20px; }
  .brand img { height: 34px; width: auto; }
  .brand span { font-weight: 700; letter-spacing: .2em; font-size: 13px; }
  h1 {
    font-family: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, "Times New Roman", serif;
    font-weight: 800; color: var(--ink); font-size: clamp(32px, 9vw, 44px); line-height: 1.05;
    margin: 4px 0 10px;
  }
  h1 em { color: var(--white); font-style: italic; }
  .sub { margin: 0 0 18px; }
  .lead { font-size: 19px; font-weight: 600; margin: 10px 0; }
  video, #strip {
    width: 100%; height: auto; display: block; background: #fff;
    border-radius: 6px; box-shadow: 0 8px 24px rgba(0,0,0,.25); margin-top: 8px;
  }
  .actions { width: 100%; display: flex; flex-direction: column; align-items: center; gap: 8px; margin: 14px 0 26px; }
  button.primary {
    width: 100%; min-height: 54px; border: 0; border-radius: 999px; cursor: pointer;
    background: var(--deep); color: var(--white); font: inherit; font-size: 19px; font-weight: 700;
  }
  button.primary:active { opacity: .8; }
  a { color: var(--white); }
  .fallback { font-size: 15px; opacity: .9; }
  .tag { font-size: 18px; margin: 6px 0; }
  .small { font-size: 15px; margin: 6px 0; }
  .muted { opacity: .85; }
  .pending { padding: 40px 0 30px; }
  .spinner {
    width: 44px; height: 44px; margin: 0 auto 8px; border-radius: 50%;
    border: 4px solid rgba(255,255,255,.35); border-top-color: #fff; animation: spin 1s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .spinner { animation: none; } }
</style>
</head>
<body>
<main>
  <div class="brand"><img src="/logo.png" alt="Emporium Thai Market"><span>PHOTOBOOTH</span></div>
  ${content}
</main>
${script ? `<script>${script}</script>` : ""}
</body>
</html>`;
}

/** Polls every 3 s until both files are there, then reloads. */
function pollScript(base: string): string {
  return `
(function () {
  function check() {
    fetch(${JSON.stringify(base + "/status")}, { cache: "no-store" })
      .then(function (r) { return r.json(); })
      .then(function (s) {
        if (s.expired || (s.strip && s.live)) { location.reload(); return; }
        setTimeout(check, 3000);
      })
      .catch(function () { setTimeout(check, 3000); });
  }
  setTimeout(check, 3000);
})();`;
}

/**
 * "Save" opens the share sheet with the file itself, so iPhone offers
 * Save Video / Save Image. Files are fetched ahead of time so the share
 * runs straight from the tap (iOS requires that). Falls back to download.
 */
function saveScript(base: string): string {
  return `
(function () {
  var files = {};
  var names = { "live.mp4": "emporium-photobooth-live.mp4", "strip.jpg": "emporium-photobooth.jpg" };
  var types = { "live.mp4": "video/mp4", "strip.jpg": "image/jpeg" };
  Object.keys(names).forEach(function (f) {
    fetch(${JSON.stringify(base)} + "/" + f)
      .then(function (r) { return r.ok ? r.blob() : null; })
      .then(function (b) { if (b) files[f] = new File([b], names[f], { type: types[f] }); })
      .catch(function () {});
  });
  document.querySelectorAll("[data-save]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var f = btn.getAttribute("data-save");
      var file = files[f];
      var fallback = ${JSON.stringify(base)} + "/" + f + "?dl=1";
      if (file && navigator.canShare && navigator.canShare({ files: [file] })) {
        navigator.share({ files: [file] }).catch(function (e) {
          if (e && e.name !== "AbortError") location.href = fallback;
        });
      } else {
        location.href = fallback;
      }
    });
  });
})();`;
}

// MARK: - Helpers

function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: { ...SECURITY_HEADERS, "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...SECURITY_HEADERS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function text(body: string, status: number, extra: Record<string, string> = {}): Response {
  return new Response(body, {
    status,
    headers: { ...SECURITY_HEADERS, "Content-Type": "text/plain; charset=utf-8", ...extra },
  });
}

function withHeaders(response: Response, extra: Record<string, string>): Response {
  const r = new Response(response.body, response);
  for (const [k, v] of Object.entries(extra)) r.headers.set(k, v);
  return r;
}
