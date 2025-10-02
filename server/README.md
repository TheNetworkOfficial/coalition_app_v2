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

## Running the server

```bash
node index.js
```

By default the server listens on [http://localhost:4000](http://localhost:4000). You can override the port by setting the `PORT` environment variable before starting the server.

## Available endpoints

- `POST /api/uploads/create` → returns a mock `{ uploadUrl, postId }`
- `POST /api/posts/metadata` → returns `{ ok: true }`
- `GET /api/feed` → returns paginated mock feed posts
- `GET /api/me/posts` → returns paginated mock posts owned by the current user

Pagination is controlled by optional `page` and `pageSize` query parameters. All data is stored in-memory and resets whenever the server restarts.
