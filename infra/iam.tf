###############################################################################################
# IAM role for EventBridge to run ECS tasks
resource "aws_iam_role" "events_role" {
  name = "${var.ecs_task_name}-events-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.ecs_task_name}-events-role"
  }
}

###############################################################################################
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
          aws_iam_role.ecs_role.arn
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

###############################################################################################
# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "${var.lambda_function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Lambda
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.lambda_function_name}-policy"
  description = "IAM policy for Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
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
          "events:PutEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:events:${var.aws_region}:*:event-bus/${var.event_bus_name}"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}


# IAM Role for Task Timeout Lambda
resource "aws_iam_role" "task_timeout_lambda_role" {
  name = "${var.task_timeout_lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# IAM Policy for Task Timeout Lambda
resource "aws_iam_policy" "task_timeout_lambda_policy" {
  name        = "${var.task_timeout_lambda_name}-policy"
  description = "IAM policy for Task Timeout Lambda function"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "ecs:ListTasks",
          "ecs:DescribeTasks",
          "ecs:StopTask"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "task_timeout_lambda_policy_attachment" {
  role       = aws_iam_role.task_timeout_lambda_role.name
  policy_arn = aws_iam_policy.task_timeout_lambda_policy.arn
}

###############################################################################################

# Single IAM role for all services
resource "aws_iam_role" "ecs_role" {
  name = "${var.ecs_task_name}-ecs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ecs-tasks.amazonaws.com",
            "lambda.amazonaws.com",
            "events.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = {
    Name      = "${var.ecs_task_name}-unified-role"
    ManagedBy = "terraform"
    Service   = "knowledge-doc-agent"
  }
}

# Single comprehensive policy with all permissions
resource "aws_iam_policy" "ecs_policy" {
  name        = "${var.ecs_task_name}-ecs-policy"
  description = "Unified policy for ECS"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:DescribeTasks",
          "ecs:ListTasks",
          "events:PutEvents",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = "secretsmanager:*"
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:TCCW-PORTKEY_API_KEY-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:TCCW-PORTKEY_VIRTUAL_KEY-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.long_term_db_password_secret}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.chroma_password_secret}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.anthropic_api_key_secret}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.openai_api_key_secret}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.huggingface_api_token_secret}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.dockerhub_username_secret}-*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.dockerhub_token_secret}-*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.source_bucket_name}",
          "arn:aws:s3:::${var.source_bucket_name}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "events:PutEvents"
        Resource = "arn:aws:events:${var.aws_region}:*:event-bus/${var.event_bus_name}"
      }
    ]
  })
}

# Attach the unified policy to the role
resource "aws_iam_role_policy_attachment" "ecs_policy_attachment" {
  role       = aws_iam_role.ecs_role.name
  policy_arn = aws_iam_policy.ecs_policy.arn
}

# Attach the AWS managed policy for ECS task execution
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
