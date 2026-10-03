# Build from the repository root (the image needs content/ too):
#   docker build -f backend/Dockerfile -t forma-backend .
FROM python:3.13-slim
WORKDIR /srv
COPY backend/pyproject.toml backend/README.md backend/constraints.txt ./backend/
COPY backend/app ./backend/app
RUN pip install --no-cache-dir -c backend/constraints.txt ./backend
COPY content /srv/content
ENV FORMA_ENV=prod FORMA_CONTENT_DIR=/srv/content PORT=8080
RUN useradd --system --uid 10001 forma
USER forma
EXPOSE 8080
# FORMA_APP_TOKENS (required in prod) and ANTHROPIC_API_KEY come from the host's secret store.
CMD ["sh", "-c", "uvicorn app.main:create_app --factory --host 0.0.0.0 --port ${PORT}"]
