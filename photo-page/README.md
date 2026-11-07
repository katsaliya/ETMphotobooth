# Photo page (Cloudflare Workers + R2)

Guests scan the QR code on the booth's screen 04 and land on
`<BASE_URL>/p/<session id>`. The page plays the looping live video and shows
the color strip, with **Save video** / **Save photo** buttons (the share sheet
on iPhone, so it offers Save Video / Save Image) and download links as a
fallback. Files are deleted automatically after 3 days.

```
booth iPad ──PUT strip.jpg / live.mp4 (X-Booth-Key)──▶ Worker ──▶ R2  sessions/<id>/…
guest phone ──GET /p/<id>────────────────────────────▶ Worker ──▶ page + media (range requests)
```

- The booth key can only **upload** the two allowed files (`image/jpeg` ≤ 10 MB,
  `video/mp4` ≤ 50 MB). There is no list, read-with-key, delete or admin route.
- Session IDs are 23 characters: 7 of creation time + 16 random. Links can't be
  guessed; the time part lets the page show "on the way…" vs "expired" with no database.
- Pages and media send `X-Robots-Tag: noindex` and `<meta name="robots" content="noindex">`.

Code: `src/index.ts`. Config: `wrangler.toml`. Logo: `public/logo.png`.

---

## One-time setup (you do these — they need your accounts)

### 1. Node.js
On this Mac, Node.js LTS (v26.13.0) is installed in `~/.local/node` (no admin
needed). Add it to your PATH once:

```bash
echo 'export PATH="$HOME/.local/node/bin:$PATH"' >> ~/.zshrc
```

Open a new Terminal window, then:

```bash
cd ~/Documents/Github/ETMphotobooth/photo-page
```

(On another computer, install the LTS from https://nodejs.org instead.)

```bash
npm install
```

### 2. Cloudflare account
Sign up (free) at https://dash.cloudflare.com/sign-up. In the dashboard, open
**R2 Object Storage** once and accept the R2 terms. The free plan needs a card
on file for R2, but stays free within 10 GB of storage.

### 3. Log in from this computer
```bash
npx wrangler login
```
A browser window opens; approve access.

### 4. Create the bucket and the 3-day delete rule
```bash
npx wrangler r2 bucket create etm-photobooth
```

```bash
npx wrangler r2 bucket lifecycle add etm-photobooth delete-after-3-days sessions/ --expire-days 3
```

### 5. Make a booth key and store it as a Worker secret
Generate a long random key:

```bash
openssl rand -base64 32
```

Then paste it when asked:

```bash
npx wrangler secret put BOOTH_KEY
```

Keep the key somewhere safe (e.g. a password manager). The iPad needs a copy.

### 6. Deploy
```bash
npx wrangler deploy
```
It prints your address, like `https://etm-photobooth.<your-subdomain>.workers.dev`.
That's the **BASE_URL**.

### 7. Point the booth at it
Copy `RecieptPhotoBooth/BoothDelivery.example.plist` to
`RecieptPhotoBooth/RecieptPhotoBooth/BoothDelivery.plist` (git-ignored), set
`BASE_URL` and `BOOTH_KEY`, and rebuild the app in Xcode.

---

## Local testing

```bash
cp .dev.vars.example .dev.vars
```

```bash
npm run dev
```

Runs at http://localhost:8787 with a local, in-memory R2. In another terminal:

```bash
npm test
```

`test/smoke.sh` checks uploads (key, type, size, file name), the pending /
ready / expired pages, noindex, content types, range requests and the download
fallback. Point it at the deployed Worker with
`BASE=https://… KEY=<booth key> npm test`.

To run the booth app in the Simulator against it, set `BASE_URL` to
`http://localhost:8787` and `BOOTH_KEY` to `local-dev-booth-key` in
`BoothDelivery.plist`. A phone can't reach `localhost`, so test scanning
against the deployed Worker.

## Later: our own domain
Add `photos.<our domain>` as a Custom Domain on the Worker
(Workers & Pages → etm-photobooth → Settings → Domains & Routes), then change
`BASE_URL` in `BoothDelivery.plist`. Nothing else changes; old workers.dev
links keep working.

## Costs (free tier)
Workers: 100k requests/day. R2: 10 GB storage, 1M uploads + 10M reads per
month, no download fees. A real session is ~5–7 MB; with 3-day expiry storage stays far under the free 10 GB.
