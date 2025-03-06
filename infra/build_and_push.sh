#!/bin/bash

# Exit if any of the intermediate steps fail
set -e

# Function for logging
log() {
    local level=$1
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" | tee -a terrastate.log
}

# Function to clean up Docker images
cleanup() {
    log "INFO" "Cleaning up Docker images..."
    docker rmi "${TASK_NAME}:${TASK_TAG}" 2>/dev/null || true
    docker rmi "${ECR_FULL_URL}" 2>/dev/null || true
}

# Function to validate AWS CLI installation
check_aws_cli() {
    if ! command -v aws &>/dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

# Assign arguments to meaningful variable names
TASK_NAME=$1
TASK_TAG=$2
ECR_URL=$3
ECR_FULL_URL=$4
REGION=$5
BUILD=${6:-"false"} # Default to false if not provided

# Validate required variables
declare -A required_vars=(
    ["TASK_NAME"]="$TASK_NAME"
    ["TASK_TAG"]="$TASK_TAG"
    ["ECR_URL"]="$ECR_URL"
    ["ECR_FULL_URL"]="$ECR_FULL_URL"
    ["REGION"]="$REGION"
)

# Check for empty required variables
missing_vars=""
for var_name in "${!required_vars[@]}"; do
    if [[ -z "${required_vars[$var_name]}" ]]; then
        missing_vars+=" $var_name"
    fi
done

if [[ -n "$missing_vars" ]]; then
    log "ERROR" "The following required variables are empty:$missing_vars"
    exit 1
fi

# Main execution block
main() {
    # Check AWS CLI installation
    check_aws_cli

    # Start the process
    log "INFO" "Starting Docker build and push process..."
    log "INFO" "Task: ${TASK_NAME}:${TASK_TAG}"
    log "INFO" "ECR URL: ${ECR_FULL_URL}"

    # Create Dockerfile if it doesn't exist
    if [[ ! -f "../Dockerfile" ]]; then
        log "INFO" "Creating Dockerfile..."
        cat >"../Dockerfile" <<'EOF'
FROM python:3.12-slim

WORKDIR /app

# Copy project files
COPY . /app/

# Install dependencies
RUN pip install --no-cache-dir -e .

# Copy lambda function to root
COPY infra/lambda/lambda_function.py /app/lambda_function.py

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Set entrypoint
ENTRYPOINT ["python", "-c", "import os, sys, json, boto3; from lambda_function import lambda_handler; event = {'Records': [{'s3': {'bucket': {'name': os.environ.get('S3_EVENT_BUCKET')}, 'object': {'key': os.environ.get('S3_EVENT_KEY')}}}]}; lambda_handler(event, None)"]
EOF
        log "INFO" "Dockerfile created successfully"
    fi

    # Log in to ECR
    log "INFO" "Logging in to ECR..."
    if ! aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URL}"; then
        log "ERROR" "Failed to log in to ECR"
        exit 1
    fi

    if [[ "${BUILD}" == "true" ]]; then
        # Build Docker image
        log "INFO" "Building Docker image..."
        if ! docker build -t "${TASK_NAME}:${TASK_TAG}" ..; then
            log "ERROR" "Docker build failed"
            exit 1
        fi

        # Tag Docker image
        log "INFO" "Tagging Docker image..."
        if ! docker tag "${TASK_NAME}:${TASK_TAG}" "${ECR_FULL_URL}"; then
            log "ERROR" "Failed to tag Docker image"
            exit 1
        fi

        # Push to ECR
        log "INFO" "Pushing to ECR..."
        if ! docker push "${ECR_FULL_URL}"; then
            log "ERROR" "Failed to push Docker image"
            exit 1
        fi

        log "SUCCESS" "Successfully pushed ${ECR_FULL_URL} to ECR"
    else
        log "INFO" "Skipping build, tag and push steps as BUILD=false"
    fi
}

# Trap for cleanup on script exit
trap cleanup EXIT

# Execute main function with error handling
{
    main "$@"
} || {
    log "ERROR" "Script failed! Check the logs above for details."
    exit 1
}
