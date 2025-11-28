# On-Device Export Plan (Most Modern Approach)

## Current Architecture (as of now)

- The Coalition app uses a non-destructive **EditManifest** / `editTimeline` to describe video edits:
  - trim
  - text overlays (`OverlayTextOp`)
  - other ops in the future
- The **Flutter client**:
  - Applies edits live in the Edit screen UI.
  - Shows overlays during the Review screen via a read-only overlay layer.
  - Shows overlays for viewers inside the app by drawing them on top of the Cloudflare Stream video at playback time.
- The **backend**:
  - Stores the `editTimeline` JSON on the post (DynamoDB + metadata).
  - Uses Cloudflare Stream for ingest and playback.
  - Does not currently apply overlays server-side; the video files stored in Cloudflare are “clean” (trimmed only).

This is a modern **non-destructive editing** setup: the original video stays clean, and overlays are applied at playback using metadata.

## Why On-Device Export Is the Long-Term Goal

Most modern consumer editors (TikTok, InShot, CapCut, etc.) do **on-device export**:

- All creative editing (text, stickers, filters) happens in the client.
- When the user taps “Post” or “Export”:
  - The app renders a final video **on the device** using the GPU / OS media APIs.
  - That final MP4 is uploaded to the backend/CDN.
- Server-side rendering is optional and reserved for special workflows (e.g., batch templates, ads, etc.).

Benefits:

- No heavy server-side ffmpeg pipelines to maintain.
- Scaling is easier and cheaper (clients do the work).
- Rendering can take full advantage of local hardware (Metal/AVFoundation, Android MediaCodec, etc.).
- The backend is mostly concerned with storage and delivery.

## Transitional State (What We Have Now)

Right now we are in a **transitional** state:

- Edits and overlays are:
  - Fully interactive in the client.
  - Persisted as `editTimeline` on the backend.
  - Applied at playback time **inside the app** via Flutter overlays.
- Videos stored in Cloudflare Stream remain clean (no burned-in text).

This is good enough for:

- All viewing inside the Coalition app.
- Rapid iteration on the editor UI and manifest format.

We have also scaffolded (in the backend repo) a potential **server-side render** pipeline, but we are intentionally not rushing to implement or enable it.

## Future Direction: On-Device Export

The long-term, “most modern” direction is:

1. Implement an on-device **export** step in the client:
   - Take the original media + `EditManifest`.
   - Use native video APIs or a video editor SDK to render a final MP4 with all overlays.
2. Upload the exported MP4 to Cloudflare as the canonical video for the post.
3. Optionally:
   - Continue storing `editTimeline` so edits can be revisited or used for analytics.
   - De-emphasize or remove any server-side rendering paths.

Until that on-device export pipeline is in place:

- The non-destructive manifest + client-side overlay rendering give us a good user experience.
- The backend render scaffolding should remain disabled (feature flag off) to avoid unnecessary complexity.

Make sure this file is committed along with the code changes so future work on the export pipeline has clear guidance.
