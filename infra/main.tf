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

# Output the ECS task definition ARN
output "ecs_task_definition_arn" {
  description = "The ARN of the ECS task definition"
  value       = aws_ecs_task_definition.tccw_knowledge_doc_agent.arn
}

# Output the ECS cluster name
output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.tccw_knowledge_doc_agent.name
}

# Output the ECR repository URL
output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.tccw_knowledge_doc_agent.repository_url
}

# Output the S3 bucket name that triggers the ECS task
output "source_bucket_name" {
  description = "The name of the S3 bucket that triggers the ECS task"
  value       = var.source_bucket_name
}

# Output the EventBridge rule ARN
output "eventbridge_rule_arn" {
  description = "The ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.lambda_event_rule.arn
}

# Output the Task Timeout Lambda ARN
output "task_timeout_lambda_arn" {
  description = "The ARN of the Task Timeout Lambda function"
  value       = aws_lambda_function.task_timeout_lambda.arn
}
