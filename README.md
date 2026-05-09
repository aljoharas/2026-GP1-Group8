# 2026-GP1-Group8 — loadout

Combined repository for the loadout project.

loadout is a cross-platform gaming activity tracker and analytics application designed to help gamers organize, analyze, and reflect on their gaming history in one centralized platform. The application allows users to log games, track achievements and playtime, manage personal game libraries, interact with friends, and receive personalized game recommendations and gameplay insights.

---

## Introduction

The gaming industry has grown into a multi-billion-dollar global market, yet players who engage
across multiple platforms — such as PlayStation, Xbox, Steam, Nintendo, and mobile — are left
with fragmented records and no unified view of their activity, as each platform stores progress
and data in isolation.

loadout addresses this by providing a centralized platform where users can:

- Track gameplay activity across multiple platforms
- Manage achievements and trophies
- Record playtime and progress
- Create custom game lists
- Rate and review games
- Receive personalized game recommendations
- View yearly gaming summaries and player insights
- Interact with friends through activity feeds

The goal of loadout is to consolidate scattered gaming data into meaningful analytics and
personalized experiences, helping users better understand and engage with their gaming habits.
---

# Technologies Used

## Frontend
- Flutter
- Dart

## Backend
- Node.js
- Express.js

## Recommender & Analytics
- Python
- Scikit-learn
- Pandas
- NumPy

## Database & Cloud Services
- Supabase (PostgreSQL)
- Firebase Authentication
- Firebase Storage
- Cloudinary

## External APIs
- RAWG API
- IGDB API
- OpenAI API / LLaMA

## Development Tools
- GitHub
- Visual Studio Code
- Android Studio

---

# Project Structure

```bash
.
├── backend/   Node.js + Express API with Python recommender service
└── flutter/   Flutter mobile application
```

---

# Launch Instructions

## 1. Clone the Repository

```bash
git clone <repository-url>
cd 2026-GP1-Group8
```

---

# Backend Setup

## Install Dependencies

```bash
cd backend
npm install
```

## Start Backend Server

```bash
npm start
```

## Required Local Files

The following files are required locally and are not included in the repository:

```bash
backend/.env
backend/serviceAccountKey.json
backend/recommender/.env
```

---

# Recommender Service Setup (Python)

## Navigate to Recommender Directory

```bash
cd backend/recommender
```

## Create Virtual Environment

```bash
python3 -m venv .venv
```

## Activate Virtual Environment

### macOS/Linux

```bash
source .venv/bin/activate
```

### Windows

```bash
.venv\Scripts\activate
```

## Install Requirements

```bash
pip install -r requirements.txt
```

## Start Recommender Service

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

---

# Flutter Application Setup

## Navigate to Flutter Project

```bash
cd flutter
```

## Install Dependencies

```bash
flutter pub get
```

## Run the Application

```bash
flutter run
```

## Required Local Files

```bash
flutter/lib/firebase_options.dart
flutter/ios/Runner/GoogleService-Info.plist
flutter/android/app/google-services.json
```

---

# Main Features

- Cross-platform game tracking
- Personal game library management
- Achievement and trophy tracking
- Playtime logging
- Game ratings and reviews
- Personalized game recommendations
- AI-powered trophy guidance
- Friend activity feed
- Custom game lists
- Annual gaming summaries
- Player archetype analysis
