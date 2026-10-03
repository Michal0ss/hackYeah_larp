PY ?= .venv/bin/python

.PHONY: install dev check lint fmt test openapi evals

install:  ## create .venv and install pinned dependencies
	python3 -m venv .venv
	$(PY) -m pip install -q -e ".[dev]" -c constraints.txt

dev:  ## run with reload on http://localhost:8000 (offline mock AI unless GEMINI_API_KEY is set)
	$(PY) -m uvicorn app.main:create_app --factory --reload --host 0.0.0.0 --port 8000

lint:
	$(PY) -m ruff check app scripts evals tests
	$(PY) -m ruff format --check app scripts evals tests

fmt:
	$(PY) -m ruff check --fix app scripts evals tests
	$(PY) -m ruff format app scripts evals tests

test:  ## unit tests (no network, no key)
	$(PY) -m pytest

evals:  ## run plan and chat checks against the real model (needs GEMINI_API_KEY), see evals/run_ai_evals.py
	$(PY) evals/run_ai_evals.py

openapi:  ## regenerate openapi.json (the API contract), validates content/ on the way
	$(PY) scripts/export_openapi.py

check: lint test  ## what CI runs: lint + tests + content validation + openapi.json up to date
	$(PY) scripts/export_openapi.py --check
	$(PY) scripts/check_texts.py  # text safety rules and the recommendation text flow (offline, no key)
	$(PY) ../scripts/sync_content.py --check  # app copy of content/ is current (run `python scripts/sync_content.py` from the repo root)
