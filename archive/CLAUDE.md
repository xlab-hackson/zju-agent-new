# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Scope

This is a pnpm workspace monorepo **only for the `zju-agent` package** — a local-first ZJU (Zhejiang University) campus AI agent. This repository is self-contained.

All commands below run from the repository root.

## Commands

```bash
pnpm install
pnpm dev:server        # backend: tsx watch on 127.0.0.1:7788 (loopback only, never public)
pnpm dev:web           # frontend: Vite on :5173, proxies /api → backend
pnpm typecheck        # tsc --noEmit across all packages (the primary verification gate)
pnpm build            # build all; web build = `pnpm --filter @zju-agent/web build`
pnpm --filter @zju-agent/server build   # build a single package by filter
```

- **No test runner is configured.** There are no `*.test.ts` files and no vitest/jest in deps. "Verification" means `pnpm typecheck` + manual end-to-end checks with real ZJU credentials (mocks cannot exercise the happy paths — see "Testing reality" below).
- **`pnpm lint` exists in the root but no package defines a `lint` script** — it is currently a no-op. Do not assume a linter runs.
- `pnpm dev` runs every app/package's `dev` in parallel; usually you want the two terminals above instead.

## Architecture

```
React Web UI (apps/web)  ──HTTP + local access token──▶  Local Fastify server (packages/server, 127.0.0.1 only)
                                                              │
                 ┌────────────────────────────────────────────┼──────────────────────────────┐
                 ▼                                            ▼                                ▼
   LLM adapter (packages/llm)                   ZJU services (packages/zju-services)       SQLite + encrypted creds
   OpenAI + Anthropic, tool calls, SSE           wraps npm `login-zju` (ZJUAM/COURSES/ZDBK)   ~/.zju-campus-agent/
```

**Hard constraint**: the frontend never touches ZJU domains, never holds the ZJU password/cookie or LLM apiKey. Every ZJU call goes through the local backend. `login-zju` is a **server-side** library — import it only in `packages/zju-services`/`packages/server`, never in `apps/web`, and never copy the upstream `login-ZJU/` source into this repo.

### Workspace layout (8 packages)

- `packages/core` — platform-agnostic types only (domain models, `ApiResponse`/`AppError`/`ErrorCode`, tool definitions). No Node-only, no React. Shared by every package including the browser, so keep it dependency-light.
- `packages/llm` — provider-agnostic LLM layer. One unified message/event type; OpenAI + Anthropic adapters translate to/from it. Supports tool calling + streaming. No Node-only APIs (uses injected `fetch`) so it needs `lib: ["ES2022","DOM"]`.
- `packages/zju-services` — wraps `login-zju`. `createZjuServices()` → lazy-loaded `ZJUAM`/`COURSES`/`ZDBK`/`CLASSROOM` instances all sharing one login. Domain adapters (`CoursesService`, `ZdbkService`, `CalendarService`, …) parse ZJU responses into `core` domain types. Also exports `semesterToXnxq01id` / `activeXnxq01ids` for 学在浙大↔教务网 semester mapping.
- `packages/server` — Fastify app. Service container (`services.ts`) holds all repos + the ZJU services + `CalendarService`. Routes under `/api/{health,bootstrap,settings,auth,zju,files,agent}`. Agent loop + tool registry live under `src/agent/`.
- `packages/storage`, `packages/scheduler` — abstraction seams reserved for future Electron/Capacitor native backends; currently thin.
- `apps/web` — React 18 + Vite + React Router + TanStack Query + Zustand + Tailwind. Pages are lazy-loaded (`src/routes/index.tsx`).

### The request flow / security model (read this before touching auth)

1. **Server boot** (`packages/server/src/index.ts`): `loadConfig` resolves `~/.zju-campus-agent/`, opens/creates `agent.db` (SQLite, WAL), builds an `EncryptedFileCredentialStore`, and reads/creates `.token` (the local access token, mode 0o600).
2. **Auth middleware** (`src/middleware/auth.ts`): every route except `/api/health` and `/api/bootstrap` requires `Authorization: Bearer <token>`. Binary resources (`<img>`/`<iframe>` previews) that can't set headers fall back to `?token=` query.
3. **Bootstrap**: dev mode hands the token to the frontend via `GET /api/bootstrap`; in production the token must be injected by Electron / read from file (not via the endpoint).
4. **Credentials**: ZJU password + LLM apiKey are stored AES-256-GCM in `~/.zju-campus-agent/credentials.enc`. Key derived from `username@hostname:appDir` (machine-bound, never written to config). The frontend only ever sees a masked `CredentialStatus`.
5. **ZJU access**: routes call `deps.auth.getServiceAdapters()` (logs in lazily, throws `ZJU_CREDENTIAL_MISSING` if no account). Do not call `login-zju` classes directly from routes — go through `AuthSessionManager`/`ZjuServices`.

### Agent loop (`packages/server/src/agent/`)

- `tools.ts` — `buildTools(deps)` registers tools, each with a `riskLevel` (`read` | `write` | `payment` | `external_download`) and `requiresConfirmation`. `read` tools execute immediately; `external_download`/write/payment tools are parked in `pending_confirmations` (5-min TTL) and only run after the user approves via `POST /api/agent/confirm`.
- `loop.ts` — `AgentLoop` runs up to 8 iterations: stream LLM → collect text + tool_calls → persist assistant message → run tools (immediate, or pause on confirm-required) → feed results back. `resumeAfterConfirm`/`resumeAfterReject` continue a paused loop. Provider is picked from the first `enabled` entry in the encrypted `model-providers` setting.
- Agent chat is **SSE**: `POST /api/agent/chat` and `/confirm` stream `data: <json>\n\n` events. Conversations + messages persist to SQLite (`conversations`/`messages` tables) and reload on reconnect.

## Conventions that will bite you if ignored

**TS config** (`tsconfig.base.json`): `moduleResolution: Bundler` + `verbatimModuleSyntax: true` → **every relative import must carry a `.js` suffix** (e.g. `./server.js`), even though the source is `.ts`. `strict` + `noImplicitOverride` + `noUnusedLocals/Parameters` + `noUncheckedIndexedAccess` are on — class overrides need `override`, and indexed access returns `T | undefined`. All packages `extends ../../tsconfig.base.json` with `noEmit: true` (builds for non-server packages are `tsc --noEmit`; this avoids TS6305 composite cross-reference churn).

**`ApiResponse` envelope + the `wrap()` trap**: every API returns `{ ok: true, data }` or `{ ok: false, error }`. `wrap(async () => …)` already wraps the result in `{ ok, data }` — so **inside `wrap`, return the raw value, never `ok(x)`**. `ok()` is only for plain synchronous handlers. Writing `return wrap(async () => { …; return ok(x); })` produces `{{ok,data:{ok,data}}}`; the frontend unwraps one layer, gets `{ok,data}` instead of an array, and `.map` throws → with no ErrorBoundary this white-screens the whole React tree. (This was a real production bug.) When adding a new read route: if it's `await` + throws `AppError`, use `wrap()` and return raw data; if it's pure sync (e.g. listing from a repo), return `ok(data)` directly.

**Error handling in the frontend**: `useCourses`/`useExams`/`useTimetable`/`useAllAssignments` use `retry: false, throwOnError: false` and consumers do `data ?? []`. Keep this pattern — an uncaught throw from a query crashes the route subtree. An `ErrorBoundary` wraps the whole app in `main.tsx`.

**ZJU file downloads — `fileId` is the upload id, not `referenceId`**: 学在浙大 files return both `id` (upload id) and `reference_id`. The download endpoint `/api/uploads/{id}/blob` takes the **upload id**. Earlier code used `referenceId ?? id` and got 404s. Always use `f.id`. Office files (`.docx/.pptx/.xlsx`) should pass `officePdf: true` to fetch the PDF preview version.

**StuId for 教务网 (zdbk)** = the ZJU credential username. Semesters are mapped between the two systems via `semesterToXnxq01id` ("2024-2025春夏" → "2024-2025-2") and `activeXnxq01ids`. The 正方 timetable endpoint is probed across two candidate paths — if real-account testing returns empty, compare against the raw response and adjust `toTimetableEntry` field names.

## Project status & deferred work

Phases 1–6 are complete and verified end-to-end (config + encrypted creds, 学在浙大 courses/materials/assignments/quizzes, 教务网 exams/timetable, LLM agent loop with tool calling + confirmation, download visualization page). **Phase 7 (智云课堂 / 校网充值) is intentionally deferred** — `ClassroomService` and `NetworkService` are stubs that throw `ZJU_SERVICE_UNAVAILABLE`; do not implement them without revisiting the deferral decision. Likely next work: assignment submission (the one missing must-have on 学在浙大) and a UI for configuring the download directory.

## Testing reality

Mocks cannot catch most real bugs here because the failure modes live on the ZJU authenticated happy path (the `wrap()` double-envelope, reversed `fileId`, weather locking ZJU login all only surfaced with real credentials). Before declaring a ZJU-touching change done, run `pnpm dev:server` + `pnpm dev:web`, configure a real ZJU account + a real LLM provider in Settings, and exercise the actual feature in the browser. Check `~/.zju-campus-agent/agent.db` `audit_logs` and confirm logs never contain passwords, cookies, or apiKeys.
