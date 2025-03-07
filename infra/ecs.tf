locals {
  account_id         = data.aws_caller_identity.current.account_id
  image_name         = "835618032093.dkr.ecr.eu-west-1.amazonaws.com/tccw-knowledge-doc-agent:latest"
  global_ecs_sg_name = "tccw-ecs-task-sg"
}
# Add this at the top of your ecs.tf file
data "aws_caller_identity" "current" {}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/aws/ecs/${var.ecs_task_name}"
  retention_in_days = 60

  # Add tags for better organization
  tags = {
    Name      = "${var.ecs_task_name}-logs"
    Service   = "knowledge-doc-agent"
    ManagedBy = "terraform"
  }
}

# Add a specific log group for the container
resource "aws_cloudwatch_log_group" "container_log_group" {
  name              = "/aws/ecs/${var.ecs_container_name}"
  retention_in_days = 60

  tags = {
    Name      = "${var.ecs_container_name}-logs"
    Service   = "knowledge-doc-agent"
    ManagedBy = "terraform"
  }
}

###############################################################################################

# ECS Cluster
resource "aws_ecs_cluster" "tccw_knowledge_doc_agent" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Get the VPC endpoint security group
data "aws_security_group" "global_ecs_sg" {
  name = local.global_ecs_sg_name
}

# EventBridge Target for ECS Task
resource "aws_cloudwatch_event_target" "ecs_task" {
  arn      = aws_ecs_cluster.tccw_knowledge_doc_agent.arn
  rule     = aws_cloudwatch_event_rule.lambda_event_rule.name
  role_arn = aws_iam_role.events_role.arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.tccw_knowledge_doc_agent.arn
    launch_type         = "FARGATE"
    task_count          = 1

    enable_ecs_managed_tags = true
    enable_execute_command  = true

    network_configuration {
      security_groups  = [data.aws_security_group.global_ecs_sg.id]
      subnets          = var.private_subnet_ids
      assign_public_ip = false
    }
  }

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket",
      key    = "$.detail.key"
    }

    input_template = <<EOF
{
  "containerOverrides": [
    {
      "name": "${var.ecs_container_name}",
      "environment": [
        {
          "name": "S3_EVENT_BUCKET",
          "value": <bucket>
        },
        {
          "name": "S3_EVENT_KEY",
          "value": <key>
        }
      ]
    }
  ]
}
EOF
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "tccw_knowledge_doc_agent" {
  family                   = var.ecs_task_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_role.arn
  task_role_arn            = aws_iam_role.ecs_role.arn

  container_definitions = jsonencode([
    {
      name      = var.ecs_container_name
      image     = local.image_name
      essential = true

      # Add port mappings to expose port 8080
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]

      # Add health check
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      environment = [
        # Optional variables from Terraform variables
        { name = "COGNITION_CONFIG_DIR", value = var.cognition_config_dir },
        { name = "CONFIG_RELOAD_TIMEOUT", value = tostring(var.config_reload_timeout) },
        { name = "APP_LOG_LEVEL", value = var.app_log_level },

        # S3 bucket configuration
        { name = "SOURCE_BUCKET_NAME", value = var.source_bucket_name },
        { name = "SOURCE_BUCKET_PREFIX", value = var.source_bucket_prefix },
        { name = "IGNORED_PREFIXES", value = join(",", var.ignored_prefixes) }
      ]

      secrets = [
        # Required variables from Secrets Manager
        { name = "PORTKEY_API_KEY", valueFrom = data.aws_secretsmanager_secret.portkey_api_key.arn },
        { name = "PORTKEY_VIRTUAL_KEY", valueFrom = data.aws_secretsmanager_secret.portkey_virtual_key.arn },

        # Optional variables from Secrets Manager
        { name = "LONG_TERM_DB_PASSWORD", valueFrom = data.aws_secretsmanager_secret.long_term_db_password.arn },
        { name = "CHROMA_PASSWORD", valueFrom = data.aws_secretsmanager_secret.chroma_password.arn },

        # API Keys
        { name = "ANTHROPIC_API_KEY", valueFrom = data.aws_secretsmanager_secret.anthropic_api_key.arn },
        { name = "OPENAI_API_KEY", valueFrom = data.aws_secretsmanager_secret.openai_api_key.arn },
        { name = "HUGGINGFACE_API_TOKEN", valueFrom = data.aws_secretsmanager_secret.huggingface_api_token.arn },

        # Docker credentials
        { name = "DOCKERHUB_USERNAME", valueFrom = data.aws_secretsmanager_secret.dockerhub_username.arn },
        { name = "DOCKERHUB_TOKEN", valueFrom = data.aws_secretsmanager_secret.dockerhub_token.arn }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.container_log_group.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs/${var.ecs_container_name}"
          "awslogs-create-group"  = "true"
          "mode"                  = "non-blocking"
          "max-buffer-size"       = "16m"
        }
      }

    }
  ])

  depends_on = [null_resource.docker_build_push]
}

