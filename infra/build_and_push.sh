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
    if command -v docker &>/dev/null; then
        docker rmi "${TASK_NAME}:${TASK_TAG}" 2>/dev/null || true
        docker rmi "${ECR_FULL_URL}" 2>/dev/null || true
    else
        log "WARN" "Docker not found, skipping cleanup"
    fi
}

# Function to validate Docker installation
check_docker() {
    if ! command -v docker &>/dev/null; then
        log "ERROR" "Docker is not installed or not in PATH. Please install Docker and ensure it's in your PATH."
        exit 1
    fi
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

    # Check Docker installation
    check_docker

    # Start the process
    log "INFO" "Starting Docker build and push process..."
    log "INFO" "Task: ${TASK_NAME}:${TASK_TAG}"
    log "INFO" "ECR URL: ${ECR_FULL_URL}"
    log "INFO" "Build flag: ${BUILD}"

    # Login to ECR
    log "INFO" "Logging in to ECR..."
    if ! aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URL}"; then
        log "ERROR" "Failed to log in to ECR"
        cleanup
        exit 1
    fi

    # Build Docker image if requested
    if [[ "${BUILD}" == "true" ]]; then
        log "INFO" "Building Docker image..."
        if ! docker build -t "${TASK_NAME}:${TASK_TAG}" ..; then
            log "ERROR" "Failed to build Docker image"
            cleanup
            exit 1
        fi

        # Tag Docker image
        log "INFO" "Tagging Docker image..."
        if ! docker tag "${TASK_NAME}:${TASK_TAG}" "${ECR_FULL_URL}"; then
            log "ERROR" "Failed to tag Docker image"
            cleanup
            exit 1
        fi

        # Push Docker image to ECR
        log "INFO" "Pushing Docker image to ECR..."
        if ! docker push "${ECR_FULL_URL}"; then
            log "ERROR" "Failed to push Docker image to ECR"
            cleanup
            exit 1
        fi

        log "INFO" "Docker image successfully built and pushed to ECR"
    else
        log "INFO" "Skipping Docker build as requested"
    fi

    cleanup
}

# Run the main function
main
