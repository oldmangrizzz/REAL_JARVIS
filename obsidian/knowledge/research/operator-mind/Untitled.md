= SPEC-1: Frontend Interface for yt-dlp based YouTube Media Access
:sectnums:
:toc:

== Background

YouTube has become the primary source of information, education, and entertainment, akin to a modern Library of Alexandria. However, the shift toward paywalls, walled gardens, and increasing subscription costs makes direct access restrictive for users who rely on the platform for personal media consumption.

This design proposes building a custom frontend for `yt-dlp`, leveraging its extensive extraction capabilities, to recreate a YouTube-like browsing experience that is user-controlled and free of platform-imposed constraints. The frontend aims to enable search, browsing, and download functionality while retaining yt-dlp's deep access features.

Thank you for clarifying and sharing the screenshots — it helps shape this properly. You’re already halfway there with your self-hosted LXC + yt-dlp base. I’m going to lock in the Requirements section next based on everything you just shared.

  

Here’s the draft — confirm, modify, or add anything before I proceed to design/method:

== Requirements

  

The system must offer a full media streaming experience leveraging yt-dlp extraction capabilities. Features follow MoSCoW prioritization:

  

=== Must Have

- Self-hosted web application interface

- Search functionality against YouTube (via yt-dlp)

- Video playback within the app (browser)

- Background play support (mobile and desktop browsers)

- Picture-in-picture mode

- Playlist creation, management, and playback

- Watch history tracking

- Local yt-dlp based download and caching for fast replay

- Responsive design for desktop and mobile

- Privacy-respecting, no 3rd-party tracking or ads

  

=== Should Have

- User authentication (local-only)

- Video metadata (title, description, duration, thumbnail)

- Option to download media (video/audio selection)

- Rate limiting or concurrency controls to avoid IP bans

  

=== Could Have

- Transcription / subtitles display

- Tagging and media library categorization

- RSS feed import/export

  

=== Won’t Have (MVP Exclusion)

- Public user registration

- Video upload

- Social features (comments/likes)

  

  

  

  

Next questions (2 max):

1. Is local user login / auth needed right now or do you prefer keeping it open (anyone on LAN can access)?

2. Should I design caching as permanent (keep downloaded videos until deleted) or temporary (auto-expire after X days)?

  

Let me know and I’ll push toward the Method (Architecture + Components) next.


== Method

The Library at Grizzlandria Research Institute is structured as a modular, self-hosted media retrieval and playback system optimized for resilience, privacy, and multi-user access.

=== High-Level Architecture
[plantuml, grizz_library_arch, png]
----
@startuml
actor User
User -> Frontend: Search / Stream / Download
Frontend -> FlaskApp: REST API Calls
FlaskApp -> yt-dlp Container: Media Extraction
FlaskApp -> Convex Vector DB: Metadata Cache
FlaskApp -> NLP Router: Route search to Provider
NLP Router -> [NLP Provider]: Process Query
FlaskApp -> Local Storage: Save media
User <- Frontend: Video Playback / Metadata / Results
@enduml
----

=== Storage Schema
Convex Collection: `media_cache`
- id (UUID)
- user_id (string)
- title (string)
- description (text)
- thumbnail (url)
- video_url (url)
- created_at (timestamp)
- expires_at (timestamp, TTL for cache eviction)

Local File Structure:

=== Components
- **Frontend:** PWA (Bootstrap + Service Worker)
- **Backend:** Flask app with Gunicorn WSGI
- **yt-dlp Docker:** Containerized for video/audio download and subtitle embedding
- **Convex.dev:** Stateless vector cache (7-day TTL)
- **NLP Router:** Dynamic routing to HuggingFace / Gemini / OpenRouter
- **Cloudflare Tunnel:** External access secured
- **User Accounts:** Optional auth for user separation (self, daughter, wife)

=== Playback System
- HTML5 video/audio tags for local streaming
- Picture-in-picture and background playback support
- Future upgrade path: HLS adaptive streaming


== Method

The Library at Grizzlandria Research Institute is a modular, self-hosted, cloud-augmented media retrieval and streaming platform. Optimized for mobile-first use, it leverages Convex for stateless persistence and Cloudflare Tunnels for secure remote access.

=== High-Level Architecture
[plantuml, grizz_library_arch, png]
----
@startuml
actor User
User -> Frontend: Search / Stream / Download
Frontend -> FlaskApp: REST API Calls
FlaskApp -> yt-dlp Docker: Media Extraction
FlaskApp -> Convex Vector DB: Metadata, Playlists, History
FlaskApp -> NLP Router: Route search to Provider
NLP Router -> [NLP Provider]: Process Query
FlaskApp -> Local Storage: Download Cache
User <- Frontend: Video Playback / Metadata / Results
@enduml
----

=== Convex Storage Schema
Collection: `media_cache`
- id (UUID)
- user_id (string)
- title (string)
- description (text)
- thumbnail (url)
- video_url (url)
- created_at (timestamp)
- expires_at (timestamp, default TTL 7 days)

Collection: `user_playlists`
- id (UUID)
- user_id (string)
- name (string)
- video_ids (array of `media_cache.id`)
- created_at (timestamp)
- updated_at (timestamp)

Collection: `watch_history`
- id (UUID)
- user_id (string)
- video_id (media_cache.id)
- watched_at (timestamp)

=== Components
- **Frontend:** PWA (Edge/iOS optimized)
- **Backend:** Flask + Gunicorn WSGI
- **yt-dlp Docker:** For audio/video download and subtitle embedding
- **Convex.dev:** Stateless metadata, playlists, history, all cloud-persistent
- **NLP Router:** Routes search to best available LLM/API
- **Cloudflare Tunnel:** Secured entry points (ex: `library.grizzlymedicine.icu`)
- **User Profiles:** Supports personal libraries per user (self, wife, daughter)

=== Playback System
- HTML5 direct playback (Edge / Safari Mobile optimized)
- Picture-in-picture and background audio
- Expandable to HLS streaming layer if needed

== Implementation

The Library at Grizzlandria Research Institute will be deployed in modular phases to enable functional use while future-proofing for Unity and iOS extensions.

=== Phase 1 — Backend Core
1. Deploy Docker stack on Proxmox node:
   - yt-dlp container (`grizz_archiver`)
   - Flask + Gunicorn backend (`grizz_app`)
   - Convex Vector DB instance (`grizz_memory`)
   - Cloudflare Tunnel (`grizz_tunnel`)
2. Integrate yt-dlp with Convex cache logic:
   - Store metadata, playlists, and watch history in Convex
   - Auto-expire media cache entries after 7 days
3. Implement NLP router for smart search (HuggingFace, Gemini, etc.)

=== Phase 2 — Frontend (Mobile-First PWA)
1. Build responsive PWA interface:
   - Video search
   - Playlists management
   - Watch history
   - Download trigger
2. Ensure playback supports:
   - HTML5 streaming
   - Picture-in-picture
   - Background audio mode on mobile (Edge/iOS)

=== Phase 3 — User Management
1. Add local user auth (lightweight username/password)
2. Assign Convex collections per user for isolation

=== Phase 4 — Cloudflare & Remote Access
1. Route app securely via:
   - `library.grizzlymedicine.icu`
2. Configure dynamic routing for Edge/iOS use cases

=== Phase 5 — Future Extensibility
1. Design API layer for Unity/iOS apps
2. Prepare knowledge graph scaffold tied to user-specific Convex vector DBs
3. Plan modular agent deployment:
   - Stateless compute per "persona"
   - Long-term memory backed by Obsidian vaults