# Mock Backend Server

This directory contains a tiny Express server that mirrors the backend endpoints the app expects. Everything is in-memory and intended purely for local development.

## Prerequisites

- [Node.js](https://nodejs.org/) 18+
- npm (bundled with Node.js)

## Setup

```bash
cd server
npm init -y
npm install express
```

The upload endpoint now integrates with Cloudflare Stream. Configure the following environment variables before running the
server:

| Variable | Description |
| --- | --- |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare account identifier. |
| `CLOUDFLARE_API_TOKEN` | API token with Stream write permissions. |
| `CLOUDFLARE_STREAM_MAX_DURATION_SECONDS` | (Optional) Override the reserved duration for newly minted uploads. Defaults to `3600`. |
| `CLOUDFLARE_STREAM_UPLOAD_EXPIRY_SECONDS` | (Optional) How long the generated upload link remains valid. Defaults to `3600`. |
| `CLOUDFLARE_STREAM_SIMPLE_UPLOAD_LIMIT_BYTES` | (Optional) Threshold for when to issue a basic form upload instead of tus. Defaults to 200 MB. |
| `CLOUDFLARE_STREAM_ALLOWED_ORIGINS` | (Optional) Comma separated list of origins allowed to play videos. |
| `CLOUDFLARE_STREAM_REQUIRE_SIGNED_URLS` | (Optional) Set to `true` to require signed playback URLs. |

## Running the server

```bash
node index.js
```

By default the server listens on [http://localhost:4000](http://localhost:4000). You can override the port by setting the `PORT` environment variable before starting the server.

## Available endpoints

- `POST /api/uploads/create` → mints a Cloudflare Stream upload URL. Requests below 200 MB receive a simple POST upload, larger
  files receive a tus upload URL.
- `POST /api/posts/metadata` → returns `{ ok: true }`
- `GET /api/feed` → returns paginated mock feed posts
- `GET /api/me/posts` → returns paginated mock posts owned by the current user

Pagination is controlled by optional `page` and `pageSize` query parameters. All data is stored in-memory and resets whenever the server restarts.
