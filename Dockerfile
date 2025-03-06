# Stage 1: Build dependencies
FROM python:3.12-slim AS builder

WORKDIR /build

# Copy necessary files for installation
COPY pyproject.toml /build/
COPY src/ /build/src/

# Install build dependencies and build the package
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir build wheel && \
    pip wheel --no-cache-dir --wheel-dir /build/wheels .

# Stage 2: Runtime
FROM python:3.12-slim

WORKDIR /app

# Copy the application code
COPY --from=builder /build/wheels /app/wheels
COPY src/ /app/src/
COPY entry.py /app/
COPY knowledge/ /app/knowledge/

# Install the application and its dependencies
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir /app/wheels/*.whl && \
    rm -rf /app/wheels

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV S3_EVENT_BUCKET=""
ENV S3_EVENT_KEY=""
ENV PYTHONPATH=/app

# Set entrypoint
ENTRYPOINT ["python", "/app/entry.py"]