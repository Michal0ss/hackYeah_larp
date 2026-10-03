PY ?= .venv/bin/python

.PHONY: install dev check lint fmt openapi

install:  ## create .venv and install pinned dependencies
	python3 -m venv .venv
	$(PY) -m pip install -q -e ".[dev]" -c constraints.txt

dev:  ## run with reload on http://localhost:8000 (offline mock AI unless ANTHROPIC_API_KEY is set)
	$(PY) -m uvicorn app.main:create_app --factory --reload --host 0.0.0.0 --port 8000

lint:
	$(PY) -m ruff check app scripts
	$(PY) -m ruff format --check app scripts

fmt:
	$(PY) -m ruff check --fix app scripts
	$(PY) -m ruff format app scripts

openapi:  ## regenerate openapi.json (the API contract), validates content/ on the way
	$(PY) scripts/export_openapi.py

check: lint  ## what CI runs: lint + content validation + openapi.json up to date
	$(PY) scripts/export_openapi.py --check
	$(PY) ../scripts/sync_content.py --check  # app copy of content/ is current (run `python scripts/sync_content.py` from the repo root)
