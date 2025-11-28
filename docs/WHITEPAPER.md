# Coalition App — Product Whitepaper (Non‑Technical)

## Overview
Coalition App is a mobile social platform for short, visual storytelling and civic engagement. It helps people:
- Create and share image and video posts quickly.
- Discover content in a personalized, scrollable feed with autoplay video.
- React and converse via likes and threaded comments.
- Build profiles, follow others, and showcase posts in a grid.
- Browse and follow civic “candidates” and their issue tags, with rich profile pages and social links.
- Apply for elevated “candidate” status and be moderated by admins.
- Run lightweight admin workflows to review applications and manage candidate tags.

This document describes what the app can do and, in plain language, how each capability works behind the scenes.

## Audience
- Non‑technical stakeholders, program leads, comms, and operations.
- Admins and moderators who need to understand the flows and guardrails.

---

## Key Capabilities

### 1) Account & Access
What it does
- Sign up and sign in with email or Google.
- Deep links return users to the app after Google sign‑in.
- Keeps users signed in across launches; supports sign out.

How it works
- The app uses a managed identity provider for authentication. It handles username rules (simple, lowercase handles), shows friendly errors, and stores a session marker so users stay signed in. On mobile, deep‑link callbacks finish Google sign‑in without manual steps.

### 2) Create: Pick, Edit, and Post
What it does
- Selects photos or videos from the device library (with one‑tap permissions prompts).
- For images: crop to common aspect ratios and rotate as needed.
- For videos: fast preview, trim start/end, and pick a cover frame (thumbnail).
- Adds an optional description and posts publicly.

How it works
- The media picker shows recent albums and items with fast thumbnails.
- Videos start playing immediately from the original file, while the app prepares an optimized “preview copy” in the background so scrubbing and trim sliders feel smooth.
- The app records non‑destructive edits (crop, trim, cover timecode) and attaches them as metadata—originals are not altered.

### 3) Reliable Uploads (Images & Video)
What it does
- Shows a top progress bar during upload.
- Uploads continue in the background; large videos are sent in resumable chunks.
- After upload, the app finalizes and publishes the post. Video posts show “processing video…” until streaming is ready.

How it works
- The app requests a one‑time “upload session” from the server and then either:
  - Uses a standard direct upload for images and small files, or
  - Uses a resumable, chunked protocol for large videos. If the network blips, it resumes from the last chunk.
- After the file reaches the media service, the app submits metadata (description, crop/trim, cover frame). It then creates the post record. While video is preparing for streaming, the app polls and shows a lightweight status banner. When ready, the post appears with a streaming URL.

### 4) Home Feed & Viewing
What it does
- A vertical, swipeable feed with images and autoplaying videos.
- Video clips play when mostly visible and pause when scrolled off‑screen.
- Tapping videos toggles play/pause; a subtle progress bar shows time remaining.

How it works
- The feed loads pages from the API and normalizes each item (ID, media URL, aspect ratio, author info). The app calculates how much of each card is visible and only auto‑plays the topmost video in view to conserve battery and data.

### 5) Likes, Comments, and Real‑Time Updates
What it does
- Tap to like/unlike a post; see like counts and open a list of likers.
- Open a comments sheet to read, reply, and like comments (with counts).
- New likes and comments update without a full refresh.

How it works
- The app does “optimistic” UI: it updates the button state and count immediately, then confirms with the server. If the server disagrees, the app corrects the count.
- A lightweight real‑time service periodically refreshes engagement summaries for posts you’re viewing and merges in comment events, so counts and threads feel live.

### 6) Profiles
What it does
- Every user has a profile: display name, avatar, bio, follower counts, and a grid of their posts.
- Users can follow/unfollow others.
- You can edit your own profile (change display name, bio, avatar) and sign out.

How it works
- When you first land on your profile, the app creates a default profile if one doesn’t exist yet.
- Avatar updates are uploaded like any image and applied immediately.
- Your profile grid merges “pending posts” (just uploaded) with published posts so you can see new content appear without navigating away.

### 7) Candidate Directory & Profiles
What it does
- Browse a scrollable list of “candidates,” each with name, level (e.g., City/State), district, tags, follower counts, and social links.
- Open a candidate’s profile, follow them, and launch their social links (e.g., X, Instagram, website).

How it works
- The directory paginates as you scroll and supports a tag‑based filter sheet for discovery (e.g., by focus area).
- Follow/unfollow uses optimistic updates: the button changes instantly while the server confirms.

### 8) Candidate Page Editing (for owners)
What it does
- Authorized users edit their candidate page: display name, level, district, bio, avatar, up to five priority tags, and social links.

How it works
- The editor validates fields and uses a tag picker sourced from an admin‑managed catalog. Social links are normalized. Avatars upload like profile images and adopt the configured delivery variant.
- Some fields can lock after approval (displayed in the UI) to preserve verified identity data.

### 9) Apply for Candidate Access
What it does
- Users without candidate access can submit an application directly in the app.

How it works
- The form collects name and contact info (email/phone optional) plus region (state/city/district). Submissions are routed to admin review. The profile header reflects status: none → pending → approved.

### 10) Admin Dashboard
What it does
- Moderators review candidate applications, open details, and approve or reject.
- Manage the candidate tag catalog: create categories, add/edit/delete tags, and control order.

How it works
- Admin pages use a simple, responsive dashboard with a navigation rail (wide screens) or tabs (small screens). Actions refresh the catalog and application queues and show success/failure snackbars.

---

## Experience Principles
- Fast by default: local video previews start immediately; uploads are resumable.
- Predictable UI: optimistic updates with corrective syncing minimize jank.
- Low friction: one‑tap permissions prompts, compact editors, and clear copy.
- Accessibility: large touch targets, readable text, and clear empty‑state guidance.

## Content & Safety
- Sign‑in protects actions like posting and commenting.
- The app normalizes inputs (usernames, tags, social links) and validates lengths.
- Admins can gate “candidate” identity and adjust discovery tags.

## Performance & Reliability
- Video optimization: a lightweight “proxy” file is generated on the device to make trimming and scrubbing smooth on slower hardware.
- Resumable video uploads: large videos send in chunks and resume on network hiccups.
- Background completion: the app keeps you informed with a compact progress bar and a video‑processing banner that clears once ready.
- Adaptive streaming: published videos use a streaming format that plays reliably across networks and devices.

## Privacy
- Sign‑in tokens are managed by the underlying identity provider; the app stores only what’s needed for the session.
- Media permissions are requested just‑in‑time and are used only for selecting and uploading your chosen files.
- Posts are currently public by default; future audience controls can be added.

## Integrations (Plain‑English)
- Identity & Sessions: Managed authentication (email + Google) with deep‑link return.
- Media Storage & Delivery: Image hosting for avatars and a streaming service for video playback.
- Large‑File Uploads: A resumable protocol is used for big video files to ensure reliability.
- Real‑Time Feel: Lightweight background refresh merges engagement changes as you view content.

## Typical User Journeys
- New user signs up → lands in the feed → creates a post → sees it appear on their profile while video finishes processing.
- Viewer scrolls feed → taps like → opens comments → replies in a thread → returns to feed with counts updated.
- Candidate updates profile → changes avatar and tags → followers see refreshed details.
- Admin reviews applications → approves one → the user’s profile shows “approved” and the candidate editor locks verified fields.

## Roadmap Considerations
- Audience controls (private/followers‑only) for posts.
- Richer discovery: search, trending tags, and location facets.
- Notifications for comment replies, likes, and application outcomes.
- Additional sign‑in providers if needed.

---

## Glossary
- Candidate: A special account type with a public page and discovery tags.
- Proxy video: A smaller, device‑optimized copy used during editing for smooth scrubbing.
- Resumable upload: A large‑file upload that can pause/resume without restarting.
- Cover frame: The still image shown before a video plays.

## Summary
Coalition App blends fast creation tools, a modern viewing experience, and pragmatic admin controls to support grassroots storytelling and civic engagement. It keeps the experience responsive on real‑world networks, gives admins the right levers to curate high‑quality candidate pages, and provides a foundation for scalable community features.

