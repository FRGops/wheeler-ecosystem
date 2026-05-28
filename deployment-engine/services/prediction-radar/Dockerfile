FROM python:3.12-slim-bookworm

# System libs required by ML packages (lightgbm→OpenMP, scikit-learn, etc.)
RUN apt-get update && apt-get upgrade -y libcap2 && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY api/requirements-pinned.txt /app/requirements.txt
COPY api/requirements.txt /app/requirements-unpinned.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY api/main.py /app/main.py
COPY api/migrate.py /app/migrate.py
COPY api/migrate.sh /app/migrate.sh
COPY scripts/infisical_entrypoint.sh /app/infisical_entrypoint.sh

COPY api/__init__.py /app/__init__.py
COPY api/core /app/core
COPY api/routes /app/routes
COPY api/services /app/services
COPY api/agents /app/agents
COPY api/integrations /app/integrations
COPY api/models /app/models
COPY api/providers /app/providers
COPY api/strategies /app/strategies
COPY api/migrations /app/migrations
COPY api/engines /app/engines
COPY api/shared /app/shared
COPY api/tests /app/tests
COPY api/config /app/config

# ML forecasting engine + exchange connectors
COPY ai /app/ai
COPY engine /app/engine
COPY strategies /app/strategies_backtest

RUN chmod +x /app/migrate.sh /app/infisical_entrypoint.sh

RUN adduser --system --no-create-home appuser
USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

ENTRYPOINT ["/app/infisical_entrypoint.sh"]
CMD ["/app/migrate.sh"]
