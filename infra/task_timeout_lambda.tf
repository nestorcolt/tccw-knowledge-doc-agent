# CloudWatch Log Group for Task Timeout Lambda
resource "aws_cloudwatch_log_group" "task_timeout_lambda_log_group" {
  name              = "/aws/lambda/${var.task_timeout_lambda_name}"
  retention_in_days = 14
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

# Create zip file for Lambda function
data "archive_file" "task_timeout_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/terminate_long_running_tasks.py"
  output_path = "${path.module}/task_timeout_lambda.zip"
}

# Lambda function
resource "aws_lambda_function" "task_timeout_lambda" {
  function_name = var.task_timeout_lambda_name
  description   = var.task_timeout_lambda_description
  role          = aws_iam_role.task_timeout_lambda_role.arn
  handler       = "terminate_long_running_tasks.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.task_timeout_lambda_timeout
  memory_size   = var.task_timeout_lambda_memory_size

  filename         = data.archive_file.task_timeout_lambda_zip.output_path
  source_code_hash = data.archive_file.task_timeout_lambda_zip.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER_NAME     = var.ecs_cluster_name
      TASK_TIMEOUT_MINUTES = var.task_timeout_minutes
      DRY_RUN              = var.task_timeout_dry_run
      APP_LOG_LEVEL        = var.app_log_level
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.task_timeout_lambda_log_group,
    aws_iam_role_policy_attachment.task_timeout_lambda_policy_attachment
  ]
}

# CloudWatch Event Rule to trigger Lambda every 5 minutes
resource "aws_cloudwatch_event_rule" "task_timeout_schedule" {
  name                = "${var.task_timeout_lambda_name}-schedule"
  description         = "Schedule for task timeout Lambda function"
  schedule_expression = "rate(5 minutes)"
}

# CloudWatch Event Target to trigger Lambda
resource "aws_cloudwatch_event_target" "task_timeout_lambda_target" {
  rule      = aws_cloudwatch_event_rule.task_timeout_schedule.name
  target_id = "${var.task_timeout_lambda_name}-target"
  arn       = aws_lambda_function.task_timeout_lambda.arn
}

# Lambda permission for CloudWatch Events
resource "aws_lambda_permission" "allow_cloudwatch_to_call_task_timeout_lambda" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.task_timeout_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.task_timeout_schedule.arn
} 
