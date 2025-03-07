locals {
  account_id = data.aws_caller_identity.current.account_id
  image_name = "835618032093.dkr.ecr.eu-west-1.amazonaws.com/tccw-knowledge-doc-agent:latest"
}
# Add this at the top of your ecs.tf file
data "aws_caller_identity" "current" {}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/aws/ecs/${var.ecs_task_name}"
  retention_in_days = 14

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
  retention_in_days = 14

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
      subnets          = var.public_subnet_ids
      assign_public_ip = true
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

  cpu    = var.ecs_task_cpu
  memory = var.ecs_task_memory

  execution_role_arn = aws_iam_role.ecs_role.arn
  task_role_arn      = aws_iam_role.ecs_role.arn

  container_definitions = jsonencode([
    {
      name  = var.ecs_container_name
      image = local.image_name

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.container_log_group.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs/${var.ecs_task_name}"
        }
      }
    }
  ])

  depends_on = [null_resource.docker_build_push]
}
