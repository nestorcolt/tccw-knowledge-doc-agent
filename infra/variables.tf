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

variable "lambda_handler" {
  description = "Handler for the Lambda function"
  type        = string
  default     = "lambda_function.lambda_handler"
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

variable "lambda_ephemeral_storage" {
  description = "Size of the Lambda function ephemeral storage (/tmp) in MB"
  type        = number
  default     = 10240 # Maximum value of 10240MB (10GB)
}

variable "lambda_code_bucket" {
  description = "S3 bucket to store Lambda deployment package"
  type        = string
  default     = "tccw-lambda-deployments"
}
