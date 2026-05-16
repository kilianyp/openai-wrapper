FROM python:3.12-slim

# UID/GID of the in-container user. Override at build time (e.g. UID=$(id -u))
# so that bind-mounted host files (like ~/.claude) are readable/writable.
ARG UID=1000
ARG GID=1000

# Install system deps (curl for Poetry installer)
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user. The Claude CLI refuses to run with
# --dangerously-skip-permissions as root, which the wrapper passes for tool use.
RUN groupadd --gid ${GID} appuser 2>/dev/null || true \
    && useradd --uid ${UID} --gid ${GID} --create-home --shell /bin/bash appuser \
    && mkdir -p /home/appuser/.local/bin /home/appuser/.local/share \
    && chown -R appuser:appuser /home/appuser/.local

# Install Poetry to a shared location so all users can invoke it
ENV POETRY_HOME=/opt/poetry
ENV PATH="/opt/poetry/bin:${PATH}"
RUN curl -sSL https://install.python-poetry.org | python3 -

# Note: Claude Code CLI is bundled with claude-agent-sdk >= 0.1.8
# No separate Node.js/npm installation required

# Copy the app code
COPY --chown=appuser:appuser . /app

# Set working directory
WORKDIR /app

USER appuser

# Install Python dependencies with Poetry (as appuser so the venv is owned correctly).
# `poetry lock` first so a stale poetry.lock doesn't block the build when
# pyproject.toml has been updated without regenerating the lock.
RUN poetry lock && poetry install --no-root \
    && ln -s "$(poetry run python -c 'import claude_agent_sdk, pathlib; print(pathlib.Path(claude_agent_sdk.__file__).parent / "_bundled" / "claude")')" /home/appuser/.local/bin/claude

# /home/appuser/.local/bin is in PATH for interactive shells via ~/.profile,
# but we want it for non-login `docker exec` too:
ENV PATH="/home/appuser/.local/bin:${PATH}"

# Expose the port
EXPOSE 8000

# Run the app with Uvicorn (development mode with reload; switch to --no-reload for prod)
CMD ["poetry", "run", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
