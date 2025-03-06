variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
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
  default     = "python3.10"
}

variable "lambda_timeout" {
  description = "Timeout for the Lambda function in seconds"
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Memory size for the Lambda function in MB"
  type        = number
  default     = 512
}

variable "lambda_handler" {
  description = "Handler for the Lambda function"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "source_bucket_name" {
  description = "Name of the S3 bucket that triggers the Lambda function"
  type        = string
}

variable "openai_api_key" {
  description = "OpenAI API Key for the Lambda function"
  type        = string
  sensitive   = true
}

variable "lambda_environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}
