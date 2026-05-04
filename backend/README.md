# Loadout

## Introduction

Loadout is a video game tracking app that lets players log the games they've played, rate and review them, track achievements, build custom lists, and follow friends' activity. The goal is to give gamers a single place to keep their gaming history and discover new titles based on what they (and their friends) have played.

## Technologies

**Backend** (this repo)
- Node.js + Express — REST API
- PostgreSQL (hosted on Supabase) — primary data store
- Firebase Admin SDK — token verification for auth
- Cloudinary — avatar/image uploads
- RAWG API + IGDB API — game metadata enrichment

**Recommender service** (`recommender/`)
- Python + FastAPI — recommendation endpoint
- scikit-learn, NumPy — content-based similarity

**Mobile client** (separate repo: `loadout_flutter`)
- Flutter / Dart
- Firebase Auth — sign-in / sign-up

## Launch instructions

### Backend API

```bash
cd loadout_backend
npm install
# Create a .env file with: DATABASE_URL, RAWG_API_KEY,
# IGDB_CLIENT_ID, IGDB_CLIENT_SECRET, CLOUDINARY_URL, RECOMMENDER_URL
# Place serviceAccountKey.json (Firebase) in the project root.
node index.js
```
Server runs on `http://localhost:3000`.

### Recommender service

```bash
cd loadout_backend/recommender
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### Flutter app

```bash
cd loadout_flutter/loadout
flutter run
```
Set `baseUrl` in [lib/core/constants.dart](../loadout_flutter/loadout/lib/core/constants.dart) before running:
- Android emulator: `http://10.0.2.2:3000`
- Physical device: `http://<your-laptop-LAN-IP>:3000` (phone and laptop on same Wi-Fi)
