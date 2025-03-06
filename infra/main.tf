terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.aws_region
}

# The S3 bucket is assumed to already exist
data "aws_s3_bucket" "source_bucket" {
  bucket = var.source_bucket_name
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

# Output the Lambda function ARN
output "lambda_function_arn" {
  description = "The ARN of the Lambda function"
  value       = aws_lambda_function.tccw_knowledge_doc_agent.arn
}

# Output the Lambda function name
output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.tccw_knowledge_doc_agent.function_name
}

# Output the S3 bucket name that triggers the Lambda
output "source_bucket_name" {
  description = "The name of the S3 bucket that triggers the Lambda"
  value       = var.source_bucket_name
}
