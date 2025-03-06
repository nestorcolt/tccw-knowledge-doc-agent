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

# IAM role for ECS task execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.ecs_task_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for ECS task execution
resource "aws_iam_policy" "ecs_execution_policy" {
  name        = "${var.ecs_task_name}-execution-policy"
  description = "IAM policy for ECS task execution"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${var.source_bucket_name}",
          "arn:aws:s3:::${var.source_bucket_name}/*"
        ]
      },
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:TCCW-*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ecs_execution_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecs_execution_policy.arn
}

# CloudWatch Log Group for ECS
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/aws/ecs/${var.ecs_task_name}"
  retention_in_days = 14
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
        { name = "PORTKEY_API_KEY", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.portkey_api_key_secret}" },
        { name = "PORTKEY_VIRTUAL_KEY", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.portkey_virtual_key_secret}" },

        # Optional variables from Secrets Manager
        { name = "LONG_TERM_DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.long_term_db_password_secret}" },
        { name = "CHROMA_PASSWORD", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.chroma_password_secret}" },

        # API Keys
        { name = "ANTHROPIC_API_KEY", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.anthropic_api_key_secret}" },
        { name = "OPENAI_API_KEY", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.openai_api_key_secret}" },
        { name = "HUGGINGFACE_API_TOKEN", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.huggingface_api_token_secret}" },

        # Docker credentials
        { name = "DOCKERHUB_USERNAME", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.dockerhub_username_secret}" },
        { name = "DOCKERHUB_TOKEN", valueFrom = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.dockerhub_token_secret}" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  depends_on = [null_resource.docker_build_push]
}

# EventBridge Rule for S3 events
resource "aws_cloudwatch_event_rule" "s3_object_created" {
  name        = "${var.ecs_task_name}-s3-event-rule"
  description = "Rule to capture S3 object creation events"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.source_bucket_name]
      }
      object = {
        key = [{
          prefix = var.source_bucket_prefix
        }]
      }
    }
  })
}

# IAM role for EventBridge to run ECS tasks
resource "aws_iam_role" "events_role" {
  name = "${var.ecs_task_name}-events-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for EventBridge to run ECS tasks
resource "aws_iam_policy" "events_policy" {
  name        = "${var.ecs_task_name}-events-policy"
  description = "IAM policy for EventBridge to run ECS tasks"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecs:RunTask"
        ]
        Effect   = "Allow"
        Resource = aws_ecs_task_definition.tccw_knowledge_doc_agent.arn
      },
      {
        Action = [
          "iam:PassRole"
        ]
        Effect = "Allow"
        Resource = [
          aws_iam_role.ecs_execution_role.arn
        ]
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "events_policy_attachment" {
  role       = aws_iam_role.events_role.name
  policy_arn = aws_iam_policy.events_policy.arn
}

# EventBridge Target for ECS Task
resource "aws_cloudwatch_event_target" "ecs_task" {
  rule      = aws_cloudwatch_event_rule.s3_object_created.name
  target_id = "${var.ecs_task_name}-target"
  arn       = aws_ecs_cluster.tccw_knowledge_doc_agent.arn
  role_arn  = aws_iam_role.events_role.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.tccw_knowledge_doc_agent.arn
    launch_type         = "FARGATE"

    network_configuration {
      subnets          = var.subnet_ids
      security_groups  = [aws_security_group.ecs_sg.id]
      assign_public_ip = true
    }
  }

  input_transformer {
    input_paths = {
      bucket = "$.detail.bucket.name",
      key    = "$.detail.object.key"
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

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_sg" {
  name        = "${var.ecs_task_name}-sg"
  description = "Security group for ECS tasks"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
