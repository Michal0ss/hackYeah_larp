# Forma backend (FastAPI)

One shared backend for the whole team. Stateless: no database, no stored videos, no stored health data. It does
four things: serves the shared content (`content/`), generates training plans, runs the AI trainer chat and
phrases the daily recommendation. Everything else (video analysis, rules engine, tempo coach, health data) stays
on the phone.

## Quick start

```bash
cd backend
make install      # venv + pinned dependencies
make dev          # http://localhost:8000  (docs: /docs)
```

Works with no key: without `ANTHROPIC_API_KEY` the AI is an offline mock (plans come from templates, chat
returns canned answers and even asks for tools, so the app side can be built offline). To use the real model:
`export ANTHROPIC_API_KEY=...` (never commit it). To force the mock even when a key is in your shell:
`FORMA_AI_MODE=mock make dev`.

From the iPhone use the Mac's address (`http://<mac-ip>:8000`); plain HTTP needs an ATS exception in debug builds.

`make check` is what CI runs: lint, content validation and "openapi.json is up to date".

## Endpoints

| Endpoint | What | Owner |
|---|---|---|
| `GET /health` | liveness, version, `aiMode`, `contentVersion` (no auth) | Michał |
| `GET /v1/catalog` | exercise catalog (ETag, 304) | Maciek |
| `GET /v1/config` | remote config: scoring, insights, tempo (ETag, 304) | Bartek / Wiktor / Michał |
| `POST /v1/plans/generate` | plan for a profile: model proposes, server validates, template as fallback | Maciek |
| `POST /v1/coach/chat` | AI trainer: SSE stream or JSON, client-executed tools | Maciek |
| `POST /v1/texts/recommendation` | friendly wording of the daily recommendation, safety-checked | Wiktor |

The contract is `openapi.json` (generated, committed). Change an endpoint or a schema, run `make openapi`,
commit both. JSON is camelCase like the Swift `Codable` types; dates are ISO 8601 UTC without fractions
(`2026-10-03T07:00:00Z`, Swift `.iso8601`). Every error is `{"error": {"code", "message", "requestId"}}`; switch
on `code`.

### Calling it from the app

- `Authorization: Bearer <token>` when `FORMA_APP_TOKENS` is set (always in prod). The token lives in
  `Config/Secrets.xcconfig`, not in the repo. It only keeps strangers from spending our model budget.
- `X-Device-Id: <random UUID the app creates once>`: rate limits are per device.
- Conversations are stateless: send the whole history every time.
- Plans and texts never fail because of the model: they answer with a template and a `warnings` entry
  (`ai_unavailable`, `ai_invalid_plan`, `ai_text_rejected`, `ai_mock`, `avoid_text_not_applied`).

### Coach chat and tools

`stream: true` (default) answers with Server-Sent Events: `delta {text}`, `tool_use {id,name,input}`,
`done {stopReason,usage}`, and `error {code,message,requestId}` if the model fails after the stream started.
`stream: false` returns one JSON object (handy for curl).

Tools are defined on the server (`app/ai/tools.py`) and executed by the **app** on local data:

1. the model answers with `tool_use` (`stopReason: "tool_use"`),
2. the app runs the tool and appends an assistant message with the `tool_use` block and a user message with a
   `tool_result` block (`toolUseId`, `content` = JSON text, a summary only),
3. the app posts again; the model answers.

Tools that read health data (`get_today_recommendation`, `get_recovery_summary`, `get_checkins`) are offered only
when `consent.health` is true. Without consent they are not in the model's tool list, health context is left out
of the prompt, and a history that contains health tool results is rejected (`consent_required`).

## Layout

```
app/main.py            app factory (create_app: settings, gateway, content injectable)
app/config.py          settings from env (FORMA_*), validated at startup
app/security.py        bearer token, device id, rate limiter
app/middleware.py      request id, size limit, access log, last-resort 500
app/errors.py          error envelope
app/schemas/           wire types (domain.py mirrors Packages/Core/Sources/Contracts)
app/content/store.py   loads + validates content/, content hashes as versions
app/ai/gateway.py      the only code that talks to Anthropic, plus the offline MockGateway
app/ai/prompts/*.md    Polish system prompts (edit wording here)
app/ai/prompts.py      fills prompts with sanitised data
app/ai/tools.py        coach tool definitions, consent gating
app/services/          plan_builder (templates), plan_validator, plan_service, coach_service,
                       text_service, safety
app/routers/           one file per area
scripts/export_openapi.py
../content/            shared content (catalog, plan templates, config): see content/README.md
```

## Rules

- No content in logs: never log bodies, prompts, chat text or health data (`logging_setup.py`). Log ids, counters,
  status and timing only. Debug a payload by reproducing it locally with the mock.
- The model proposes, the server decides: validate everything the model returns, keep a template fallback.
- No diagnoses (PROJECT.md 3.6). Prompts say it, `services/safety.py` enforces part of it. Extend the patterns
  when you find a miss.
- Free text from users is data: `sanitize_free_text` before it enters a prompt.
- API keys and tokens only in the environment of the machine that runs the server.
- Adding an endpoint: schema in `app/schemas/api.py`, logic in `app/services/`, thin router in `app/routers/`,
  register in `app/routers/__init__.py`, `make openapi`.

## Deploying

**Vercel (prepared, never deployed yet).** Files at the repo root: `api/index.py` (exposes `app`), `vercel.json`
(rewrites everything to it, 60 s limit, bundles `backend/app` and `content/`), `requirements.txt` (pinned runtime
dependencies, keep in sync with `backend/constraints.txt`), `.vercelignore`. Steps:

1. Import the GitHub repo in Vercel; leave the Root Directory as the repo root and the framework as "Other".
2. Project environment variables (all environments): `FORMA_APP_TOKENS` (required, one or more random strings),
   `ANTHROPIC_API_KEY` (optional: without it the server stays in mock mode). Nothing else is required.
3. Deploy. Check `https://<project>.vercel.app/health` (`aiMode` shows `mock` or `anthropic`).
4. Everyone sets `FORMA_API_URL=https://<project>.vercel.app` and `FORMA_API_TOKEN=<one of the tokens>` in
   `Config/Secrets.xcconfig`. Every branch gets its own preview URL.

Known gaps to check on the first deploy: SSE streaming through the function, the 60 s limit for the coach, cold
starts, and rate limits that live in memory (per instance, so they barely work on Vercel: move them to Supabase
or rely on the token and the spending limit on the key). Plan generation allows 45 s, which fits the limit.

`docker build -f backend/Dockerfile -t forma-backend .` from the repository root is the fallback (untested: no
Docker on the build machine). In prod the docs and the schema endpoint are off.
