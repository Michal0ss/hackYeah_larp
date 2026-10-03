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

Works with no key: without `GEMINI_API_KEY` the AI is an offline mock (plans come from templates, chat
returns canned answers and even asks for tools, so the app side can be built offline). To use the real model
(Google Gemini): `export GEMINI_API_KEY=...` or put it in `backend/.env` (git-ignored; never commit it). To force
the mock even when a key is set: `FORMA_AI_MODE=mock make dev`.

Use a key from a **paid** (billing-enabled) Google AI project with a budget limit. On the free tier Google may use
prompts to improve its products (coach prompts carry health summaries) and the quota is tiny: 20 requests per
day per model, after which every call answers 429.

### Models and what happens when Gemini misbehaves

`FORMA_COACH_MODEL`, `FORMA_PLAN_MODEL` and `FORMA_TEXT_MODEL` (default `gemini-3.5-flash`) pick the model;
`FORMA_FALLBACK_MODELS` (comma-separated) lists the ones that take over. See what a key can use with
`.venv/bin/python evals/run_ai_evals.py --list-models`.

- A call moves to the next model on 404 (retired), 429 (quota), 5xx, timeout or connection error. A chat stream
  moves on only while nothing was sent to the app yet.
- A model that answered 429 or 404 is skipped for 5 min or 1 h, so following requests do not wait for the same
  failure again. With every model cooling down the first one is tried anyway.
- When no model works: plans and texts are answered from templates (`warnings: ["ai_unavailable"]`), the chat
  answers `503 ai_unavailable` (or an `error` event in a stream) and the app shows its retry message.
- Plans and texts have deadlines (`plan_deadline_seconds` 50 s, kept under the 60 s Vercel limit, and `text_deadline_seconds`); one request to one model is
  capped by `ai_timeout_seconds`. Thinking is kept low, and token limits are generous because thinking tokens
  count against them.

`make test` runs the unit tests (no network, no key): they use a fake Gemini client. `make evals` checks the real
model (needs a key and quota).

From the iPhone use the Mac's address (`http://<mac-ip>:8000`); plain HTTP needs an ATS exception in debug builds.

`make check` is what CI runs: lint, unit tests, content validation and "openapi.json is up to date".

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

`propose_plan_change` is the one tool that is not a read, and it still never writes: the app turns the call into a
card ("Zastosuj" / "Odrzuć") and the plan changes only when the user taps it. The server keeps only valid parts of
the input (kind, weekdays 1 to 7, catalog ids, a replacement that fits the person's equipment, level and avoided
movements, a short reason that passes the generated-text checks); the app checks the request against the real plan
and answers the model with an error it can explain when the change is not possible.

Tools that read health data (`get_today_recommendation`, `get_recovery_summary`, `get_checkins`,
`get_session_feedback`) are offered only when `consent.health` is true. Without consent they are not in the model's
tool list, health context is left out of the prompt, and a history that contains health tool results is rejected
(`consent_required`).

The request also carries a small **context** that the server turns into the system prompt (`app/ai/prompts.py`), so
simple questions need no tool call:

- `profile` and `todayRecommendation` (the recommendation only with consent),
- `snapshot` (`TrainingSnapshot`): today's session, the week and the last technique result, as ids and numbers. The
  session's `adaptationNote` and its `adapted` status come from health signals, so the server ignores them without
  consent (the app leaves them out as well),
- `workout` (`WorkoutContext`): the screen the question was asked from and the last set as numbers (training data,
  no health data; it makes the coach answer in at most three sentences while the user is exercising).

Everything in the context is data, not an instruction: free text goes through `sanitize_free_text`, exercises are
named from the catalog, and the catalog in the prompt is split into exercises that fit this person (equipment, level,
movements to avoid) and the rest, so substitutes are always suitable.

## Layout

```
app/main.py            app factory (create_app: settings, gateway, content injectable)
app/config.py          settings from env (FORMA_*), validated at startup
app/security.py        bearer token, device id, rate limiter
app/middleware.py      request id, size limit, access log, last-resort 500
app/errors.py          error envelope
app/schemas/           wire types (domain.py mirrors Packages/Core/Sources/Contracts)
app/content/store.py   loads + validates content/, content hashes as versions
app/ai/gateway.py      gateway interface and the offline MockGateway
app/ai/gemini.py       Gemini gateway: tool translation, model fallback, cooldown (the only code that calls Google)
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

**Vercel (deployed 2026-10-03).** Project `forma-api` in the team `michal-team00`, production URL
`https://forma-api-three.vercel.app` (region fra1, no Vercel Authentication, so the app token is the only gate).
Files at the repo root: `api/index.py` (exposes `app`), `vercel.json` (everything rewritten to it, 60 s limit),
`requirements.txt` (pinned runtime dependencies, keep in sync with `backend/constraints.txt`), `.vercelignore`.

Environment variables of the Vercel project (Settings, or `npx vercel env add NAME production`):

| Name | Needed | What |
|---|---|---|
| `FORMA_APP_TOKENS` | yes | the app token(s); the server refuses to start without it. Set. |
| `GEMINI_API_KEY` | for the real model | key from a **paid** Google project with a budget limit. Not set yet: without it the server answers in mock mode (`/health` shows `aiMode: mock`). |

Redeploy: `npx vercel deploy --prod --yes --scope michal-team00` from the repo root (the CLI must be logged in:
`npx vercel login`). Changing an environment variable needs a redeploy. Logs: Vercel dashboard, or the MCP tool
`get_runtime_logs`.

App side: `FORMA_API_URL` and `FORMA_API_TOKEN` in `Config/Secrets.xcconfig` (gitignored). Ask Michał for the token.

Lessons from the first deploy (so nobody repeats them):
- `.vercelignore` matching is **case-insensitive**: a plain `App/` also removed `backend/app/` and the function
  failed with `No module named 'app'`. Anchor patterns with a leading `/`.
- `includeFiles` with brace globs did not include the backend; the Python runtime bundles the project by default.
- The GitHub integration was not connected for this repo, so deploys are made from the CLI, not by pushing.

Known gaps: rate limits live in memory (per instance, so they barely work on Vercel: rely on the token and the
spending limit on the key), cold starts, the Gemini key signature cache is per process.

`docker build -f backend/Dockerfile -t forma-backend .` from the repository root is the fallback (untested: no
Docker on the build machine). In prod the docs and the schema endpoint are off.
