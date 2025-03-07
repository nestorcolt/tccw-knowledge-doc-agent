variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "tccw-knowledge-doc-agent"
}

variable "lambda_description" {
  description = "Description of the Lambda function"
  type        = string
  default     = "Lambda function for TCCW Knowledge Document Agent"
}

variable "lambda_runtime" {
  description = "Runtime for the Lambda function"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 1024
}

variable "source_bucket_name" {
  description = "Name of the S3 bucket that triggers the Lambda function"
  default     = "tccw-work-pipiline-entry"
  type        = string
}

variable "source_bucket_prefix" {
  description = "Prefix in the S3 bucket that triggers the Lambda function"
  type        = string
  default     = "knowledge_base/"
}

variable "cognition_config_dir" {
  description = "Configuration directory path"
  type        = string
  default     = "/opt/config"
}

variable "config_reload_timeout" {
  description = "Config reload timeout (default: 0.1)"
  type        = number
  default     = 0.1
}

variable "app_log_level" {
  description = "Logging level (default: INFO)"
  type        = string
  default     = "INFO"
}

# Secret names with TCCW naming convention
variable "portkey_api_key_secret" {
  description = "Name of the secret containing Portkey API Key"
  type        = string
  default     = "TCCW-PORTKEY_API_KEY-SECRET"
}

variable "portkey_virtual_key_secret" {
  description = "Name of the secret containing Portkey Virtual Key"
  type        = string
  default     = "TCCW-PORTKEY_VIRTUAL_KEY-SECRET"
}

variable "long_term_db_password_secret" {
  description = "Name of the secret containing PostgreSQL database password"
  type        = string
  default     = "TCCW-LONG_TERM_DB_PASSWORD-SECRET"
}

variable "chroma_password_secret" {
  description = "Name of the secret containing ChromaDB password"
  type        = string
  default     = "TCCW-CHROMA_PASSWORD-SECRET"
}

variable "anthropic_api_key_secret" {
  description = "Name of the secret containing Anthropic API Key"
  type        = string
  default     = "TCCW-ANTHROPIC_API_KEY-SECRET"
}

variable "openai_api_key_secret" {
  description = "Name of the secret containing OpenAI API Key"
  type        = string
  default     = "TCCW-OPENAI_API_KEY-SECRET"
}

variable "huggingface_api_token_secret" {
  description = "Name of the secret containing HuggingFace API Token"
  type        = string
  default     = "TCCW-HUGGINGFACE_API_TOKEN-SECRET"
}

variable "dockerhub_username_secret" {
  description = "Name of the secret containing DockerHub Username"
  type        = string
  default     = "TCCW-DOCKERHUB_USERNAME-SECRET"
}

variable "dockerhub_token_secret" {
  description = "Name of the secret containing DockerHub Token"
  type        = string
  default     = "TCCW-DOCKERHUB_TOKEN-SECRET"
}

variable "ignored_prefixes" {
  description = "List of prefixes to ignore when processing S3 events"
  type        = list(string)
  default     = [".write/"]
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository"
  type        = string
  default     = "tccw-knowledge-doc-agent"
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
  default     = "tccw-knowledge-doc-agent-cluster"
}

variable "ecs_task_name" {
  description = "Name of the ECS task"
  type        = string
  default     = "tccw-knowledge-doc-agent-task"
}

variable "ecs_container_name" {
  description = "Name of the container in the ECS task"
  type        = string
  default     = "tccw-knowledge-doc-agent-container"
}

variable "ecs_task_cpu" {
  description = "CPU units for the ECS task"
  type        = number
  default     = 1024
}

variable "ecs_task_memory" {
  description = "Memory for the ECS task in MB"
  type        = number
  default     = 2048
}

variable "vpc_id" {
  description = "VPC ID for ECS tasks"
  type        = string
  default     = "vpc-0aed058acd6e3328a" # Replace with your VPC ID
}

variable "public_subnet_ids" {
  description = "Subnet IDs for ECS tasks"
  type        = list(string)
  default     = ["subnet-08ee7afbabfbbac9c", "subnet-0794a5e45c9fce58c"] # Replace with your subnet IDs
}

variable "private_subnet_ids" {
  description = "Subnet IDs for ECS tasks"
  type        = list(string)
  default     = ["subnet-0853cb0854eb070ec", "subnet-046c3c44cf3672673"] # Replace with your subnet IDs
}

variable "build_docker_image" {
  description = "Whether to build the Docker image during Terraform apply"
  type        = bool
  default     = false
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
  default     = "default"
}

# Task Timeout Lambda variables
variable "task_timeout_lambda_name" {
  description = "Name of the Task Timeout Lambda function"
  type        = string
  default     = "tccw-knowledge-doc-agent-task-timeout"
}

variable "task_timeout_lambda_description" {
  description = "Description of the Task Timeout Lambda function"
  type        = string
  default     = "Lambda function to terminate long-running ECS tasks"
}

variable "task_timeout_lambda_timeout" {
  description = "Timeout for the Task Timeout Lambda function in seconds"
  type        = number
  default     = 300
}

variable "task_timeout_lambda_memory_size" {
  description = "Memory size for the Task Timeout Lambda function in MB"
  type        = number
  default     = 128
}

variable "task_timeout_minutes" {
  description = "Maximum allowed runtime for ECS tasks in minutes before termination"
  type        = number
  default     = 20
}

variable "task_timeout_dry_run" {
  description = "If true, the Lambda will log tasks to terminate but not actually terminate them"
  type        = string
  default     = "false"
}
