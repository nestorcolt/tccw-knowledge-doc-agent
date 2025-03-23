terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "tccw-europe-infra-bucket"
    key    = "terraform/ai-agent/knowledge-base.tfstate"
    region = "eu-west-1"
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "ai_agent" {
  source = "git::https://github.com/nestorcolt/tccw-ecs-task-builder.git"

  # Core configuration
  aws_region       = "eu-west-1"
  ecs_cluster_name = "tccw-agentic-pipeline-cluster"
  task_name        = "tccw-knowledge-base-agent"
  debug_mode       = false

  #  Event source configuration
  sqs_event_trigger_arn = "arn:aws:sqs:eu-west-1:835618032093:tccw-knowledge-base-queue"

  # Task configuration
  task_register_table_name = "tccw-agent-tasks"
  task_timeout_seconds     = 3600
  task_memory_mb           = 2048
  task_cpu_units           = 1024

  task_environment_variables = {
    COGNITION_CONFIG_SOURCE = "git@github.com:nestorcolt/cognition-config.git"
    COGNITION_CONFIG_DIR    = "~/.cognition/tccw-knowledge-doc-agent/config"
    ENV_FILE_SECRET_ID      = "tccw-agent-env-variables"
    GITHUB_PEM_SECRET_ID    = "TCCW-GITHUB-PEM"
    APP_LOG_LEVEL           = "DEBUG"
  }

  # Container configuration
  container_port     = 8080
  enable_healthcheck = true

  # Optional health check configuration
  healthcheck_command      = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
  healthcheck_interval     = 30
  healthcheck_timeout      = 5
  healthcheck_retries      = 3
  healthcheck_start_period = 60

  # Infrastructure configuration
  cpu_architecture       = "ARM64"
  ephemeral_storage_size = 21

  # ECR image lifecycle configuration
  dockerfile_path                = "${path.root}/Dockerfile"
  latest_tag_retention_count     = 5
  versioned_tag_retention_count  = 10
  versioned_tag_prefixes         = ["v", "release", "dev"]
  untagged_image_expiration_days = 7
  force_build                    = true
}
