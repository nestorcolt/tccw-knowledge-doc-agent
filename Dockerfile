FROM python:3.12-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends git openssh-client curl unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
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
RUN mkdir -p /root/.ssh && \
    ssh-keyscan bitbucket.org >> /root/.ssh/known_hosts && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# Set entrypoint to fetch SSH key from AWS Secrets Manager, run the main module, and then sleep
ENTRYPOINT ["sh", "-c", "\
    aws secretsmanager get-secret-value --secret-id $GITHUB_PEM_SECRET_ID --query SecretString --output text > /root/.ssh/id_rsa && \
    aws secretsmanager get-secret-value --secret-id $ENV_FILE_SECRET_ID --query SecretString --output text > /root/.env && \
    chmod 600 /root/.ssh/id_rsa && \
    DEBUG_MODE=false && \
    aws dynamodb get-item --table-name $AGENT_TASKS_TABLE_NAME --key '{\"task_id\":{\"S\":\"'$TASK_ID'\"}}' > /app/config.json 2>/dev/null || echo '{\"Item\":{}}' > /app/config.json && \
    if grep -q '\"debug_mode\":{\"BOOL\":true}' /app/config.json; then \
    DEBUG_MODE=true; \
    echo 'Debug mode enabled from DynamoDB configuration'; \
    else \
    echo 'Debug mode disabled (default or from DynamoDB configuration)'; \
    fi && \
    { python -m tccw_knowledge_doc_agent.main || echo 'Main module failed with exit code $?'; } && \
    if [ \"$DEBUG_MODE\" = \"true\" ]; then \
    echo 'Container sleeping for 30 MINS for debugging...' && \
    sleep 1800; \
    else \
    echo 'Debug mode disabled, container exiting normally'; \
    fi"]