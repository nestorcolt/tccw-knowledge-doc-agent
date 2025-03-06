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

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}

# Create zip file for Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/launch_job.py"
  output_path = "${path.module}/lambda_function.zip"
}

# Lambda function
resource "aws_lambda_function" "launch_job" {
  function_name = var.lambda_function_name
  description   = var.lambda_description
  role          = aws_iam_role.lambda_role.arn
  handler       = "launch_job.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SOURCE_BUCKET_NAME   = var.source_bucket_name
      SOURCE_BUCKET_PREFIX = var.source_bucket_prefix
      IGNORED_PREFIXES     = join(",", var.ignored_prefixes)
      ECS_CLUSTER_NAME     = var.ecs_cluster_name
      ECS_TASK_NAME        = var.ecs_task_name
      ECS_CONTAINER_NAME   = var.ecs_container_name
      EVENT_BUS_NAME       = var.event_bus_name
      APP_LOG_LEVEL        = var.app_log_level
    }
  }

  ephemeral_storage {
    size = var.lambda_ephemeral_storage
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_log_group,
    aws_iam_role_policy_attachment.lambda_policy_attachment
  ]
}

# S3 event notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = var.source_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.launch_job.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.source_bucket_prefix
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# Lambda permission for S3
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.launch_job.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.source_bucket_name}"
} 
