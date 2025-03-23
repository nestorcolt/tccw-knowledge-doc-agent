FROM python:3.12-slim

WORKDIR /app
ARG CPU_ARCHITECTURE=x86_64

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends git openssh-client curl unzip jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN echo "########################################################################################"
RUN echo "# CPU Architecture: $CPU_ARCHITECTURE"
RUN echo "########################################################################################"

# Install AWS CLI v2 based on architecture
RUN if [ "$CPU_ARCHITECTURE" = "arm64" ]; then \
    echo "Installing ARM64 AWS CLI -----------------------------------------------------------" && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"; \
    else \
    echo "Installing X86_64 AWS CLI -------------------------------------------------------------" && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; \
    fi && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Copy application files
COPY pyproject.toml /app/
COPY src/ /app/src/
COPY knowledge/ /app/knowledge/

# Install the application
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -e .

RUN crewai install

# Set environment variables
ENV AGENT_TASKS_TABLE_NAME=""
ENV GITHUB_PEM_SECRET_ID=""
ENV ENV_FILE_SECRET_ID=""
ENV PYTHONUNBUFFERED=1
ENV S3_BUCKET_NAME=""
ENV S3_OBJECT_KEY=""
ENV PYTHONPATH=/app
ENV TASK_ID=""

# Create SSH directory
RUN mkdir -p /root/.ssh
RUN touch /root/.ssh/id_rsa 
RUN chmod 600 /root/.ssh/id_rsa \
    && ssh-keyscan github.com >> /root/.ssh/known_hosts

# Set entrypoint to fetch SSH key from AWS Secrets Manager, run the main module, and then sleep
ENTRYPOINT ["sh", "-c", "\
    aws secretsmanager get-secret-value --secret-id $GITHUB_PEM_SECRET_ID --query SecretString --output text > /root/.ssh/id_rsa && \
    aws secretsmanager get-secret-value --secret-id $ENV_FILE_SECRET_ID --query SecretString --output text > /root/.env && \
    aws dynamodb get-item --table-name $AGENT_TASKS_TABLE_NAME --key '{\"task_id\":{\"S\":\"'$TASK_ID'\"}}' > /app/config.json 2>/dev/null || echo '{\"Item\":{}}' > /app/config.json && \
    DEBUG_MODE=$(jq -r '.Item.debug_mode.BOOL // false' /app/config.json) && \
    echo \"Debug mode: $DEBUG_MODE\" && \
    { crewai run || echo 'Main module failed with exit code $?'; } && \
    if [ \"$DEBUG_MODE\" = \"true\" ]; then \
    echo 'Container sleeping for 30 MINS for debugging...' && \
    sleep 1800; \
    else \
    echo 'Debug mode disabled, container exiting normally'; \
    fi"]