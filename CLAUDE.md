# Card Vault App — Claude Guidelines

## Language

All code, comments, documentation, and generated content must be written in **English**.

## Comments

All Dart files must include comments:
- Every class must have a brief doc comment (`///`) explaining its purpose.
- Every public method must have a doc comment explaining what it does.
- Non-obvious logic blocks must have an inline comment explaining the *why*.
- File-level doc comments are encouraged for core modules.

## Project Overview

Flutter app for managing MTG card collections. Targets iOS and Android.

**Backend**: Go REST API at `../card-vault-backend` (local: `http://localhost:8080`)  
**Auth**: JWT access + rotating refresh tokens  
**Key feature**: Continuous camera scan with ML Kit OCR to identify and add cards  

## Architecture

Feature-modular layout mirroring the backend:

```
lib/
├── main.dart               # Entry point — initialises cameras + providers
├── app.dart                # Root widget, go_router config, auth guard
├── core/
│   ├── api/                # Dio client + JWT interceptor
│   ├── auth/               # Token storage + auth repository
│   ├── models/             # Shared data models (Card, Collection, ScanHints…)
│   └── providers.dart      # Root Riverpod providers
└── features/
    ├── auth/               # Login + register screens
    ├── scan/               # Scanner screen + OCR controller
    ├── collections/        # Collections list + detail screens
    └── home/               # Tab shell (Scan | Collections)
```

## Key Conventions

- State management: **Riverpod** (`flutter_riverpod`)
- Routing: **go_router** with auth redirect
- HTTP: **Dio** with `AuthInterceptor` (auto-refresh on 401)
- Secure storage: **flutter_secure_storage**
- OCR: **google_mlkit_text_recognition** (Latin script)

## Scanner Design

Continuous scan — no "take photo" button:
1. Camera live preview at `ResolutionPreset.medium`
2. One frame sampled every 350 ms via `startImageStream`
3. ML Kit OCR on each sampled frame
4. Extract hints: `name`, `set_code`, `collector_number` via `OcrExtractor`
5. Stability check: 3 consecutive identical readings required
6. On stable: call `POST /api/v1/cards/resolve`
7. `exact` → card preview overlay; `candidates` → bottom sheet picker

## Backend API Base

Local development: `http://localhost:8080`  
All `/api/v1/*` routes require `Authorization: Bearer <access_token>`.
