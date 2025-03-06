# Add this at the top of your ecs.tf file
data "aws_caller_identity" "current" {}

# ECR Repository for Docker image
resource "aws_ecr_repository" "tccw_knowledge_doc_agent" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "tccw_knowledge_doc_agent" {
  repository = aws_ecr_repository.tccw_knowledge_doc_agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Keep last 3 images with 'latest' tag",
        selection = {
          tagStatus      = "tagged",
          tagPatternList = ["latest"],
          countType      = "imageCountMoreThan",
          countNumber    = 3
        },
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2,
        description  = "Expire untagged images older than 30 days",
        selection = {
          tagStatus   = "untagged",
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 30
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Null resource to build and push Docker image
resource "null_resource" "docker_build_push" {
  count = var.build_docker_image ? 1 : 0

  triggers = {
    dockerfile_md5   = fileexists("${path.module}/../Dockerfile") ? filemd5("${path.module}/../Dockerfile") : timestamp()
    entry_script_md5 = fileexists("${path.module}/../entry.py") ? filemd5("${path.module}/../entry.py") : timestamp()
    pyproject_md5    = fileexists("${path.module}/../pyproject.toml") ? filemd5("${path.module}/../pyproject.toml") : timestamp()
    build_script_md5 = filemd5("${path.module}/build_and_push.sh")
    src_code_hash    = sha256(join("", [for f in fileset("${path.module}/../src", "**/*.py") : filemd5("${path.module}/../src/${f}")]))
  }

  provisioner "local-exec" {
    command = <<-EOT
      if command -v docker &>/dev/null; then
        bash ${path.module}/build_and_push.sh ${var.ecr_repository_name} latest ${aws_ecr_repository.tccw_knowledge_doc_agent.repository_url} ${aws_ecr_repository.tccw_knowledge_doc_agent.repository_url}:latest ${var.aws_region} true
      else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] Docker not found. Skipping image build and push. You will need to build and push the image manually."
      fi
    EOT
  }

  depends_on = [aws_ecr_repository.tccw_knowledge_doc_agent]
}

# ECS Cluster
resource "aws_ecs_cluster" "tccw_knowledge_doc_agent" {
  name = var.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

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

# Data sources for secrets
data "aws_secretsmanager_secret" "portkey_api_key" {
  name = var.portkey_api_key_secret
}

data "aws_secretsmanager_secret" "portkey_virtual_key" {
  name = var.portkey_virtual_key_secret
}

data "aws_secretsmanager_secret" "long_term_db_password" {
  name = var.long_term_db_password_secret
}

data "aws_secretsmanager_secret" "chroma_password" {
  name = var.chroma_password_secret
}

data "aws_secretsmanager_secret" "anthropic_api_key" {
  name = var.anthropic_api_key_secret
}

data "aws_secretsmanager_secret" "openai_api_key" {
  name = var.openai_api_key_secret
}

data "aws_secretsmanager_secret" "huggingface_api_token" {
  name = var.huggingface_api_token_secret
}

data "aws_secretsmanager_secret" "dockerhub_username" {
  name = var.dockerhub_username_secret
}

data "aws_secretsmanager_secret" "dockerhub_token" {
  name = var.dockerhub_token_secret
}

# ECS Task Definition
resource "aws_ecs_task_definition" "tccw_knowledge_doc_agent" {
  family                   = var.ecs_task_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = var.ecs_container_name
      image     = "${aws_ecr_repository.tccw_knowledge_doc_agent.repository_url}:latest"
      essential = true

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

      startTimeout = 120 # Give the container 2 minutes to start up and fetch secrets
    }
  ])

  depends_on = [null_resource.docker_build_push]
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name        = "${var.ecs_task_name}-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Optional: Add specific rules for HTTPS (port 443) to AWS services
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS outbound traffic to AWS services"
  }
}

# Update the test script to check the correct log group
resource "null_resource" "update_test_script" {
  triggers = {
    log_group_name = aws_cloudwatch_log_group.container_log_group.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      if [ -f "${path.module}/../tests/fargate_test.py" ]; then
        sed -i 's|log_group_name = f"/aws/ecs/tccw-knowledge-doc-agent-task"|log_group_name = "${aws_cloudwatch_log_group.container_log_group.name}"|g' ${path.module}/../tests/fargate_test.py
        echo "Updated log group name in test script to ${aws_cloudwatch_log_group.container_log_group.name}"
      fi
    EOT
  }

  depends_on = [aws_cloudwatch_log_group.container_log_group]
}
