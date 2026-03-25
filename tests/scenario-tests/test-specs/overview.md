# Todo App — Overview

## Goal

A full-stack todo app supporting create, edit, complete, delete, and priority levels.

## Tech Stack

- **Frontend:** React 18, Vite, TypeScript, Tailwind CSS, shadcn/ui
- **Backend:** Express, TypeScript, better-sqlite3
- **Testing:** Vitest, Supertest, React Testing Library, Playwright
- **Dev:** Vite proxies `/api/*` to Express on :3001; production serves built client from Express

## Architecture

Monorepo with two workspaces:
- `client/` — Vite + React SPA, owns all UI state
- `server/` — Express REST API, owns all persistence

```
todo-test-vanilla/
├── package.json          # root workspaces + concurrently scripts
├── client/               # Vite + React + TypeScript
├── server/               # Express + TypeScript + SQLite
└── e2e/                  # Playwright tests
```

## Running the App

```bash
npm install
npm run dev        # starts both client (:5173) and server (:3001) concurrently
npm run build      # builds client; server serves static from dist/
npm test           # unit + integration tests
npm run test:e2e   # Playwright tests
```
