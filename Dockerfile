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
ENV GITHUB_PEM_SECRET_ID=""
ENV PYTHONUNBUFFERED=1
ENV S3_EVENT_BUCKET=""
ENV S3_EVENT_KEY=""
ENV PYTHONPATH=/app

# Create SSH directory
RUN mkdir -p /root/.ssh && \
    ssh-keyscan bitbucket.org >> /root/.ssh/known_hosts && \
    ssh-keyscan github.com >> /root/.ssh/known_hosts

# Set entrypoint to fetch SSH key from AWS Secrets Manager, run the main module, and then sleep
ENTRYPOINT ["sh", "-c", "\
    aws secretsmanager get-secret-value --secret-id $GITHUB_PEM_SECRET_ID --query SecretString --output text > /root/.ssh/id_rsa && \
    chmod 600 /root/.ssh/id_rsa && \
    { python -m tccw_knowledge_doc_agent.main || echo 'Main module failed with exit code $?'; } && \
    echo 'Container sleeping for 30 MINS for testing...' && \
    sleep 1800"]