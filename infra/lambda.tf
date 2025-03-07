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

# Lambda launch job function
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

###############################################################################################
# CloudWatch Log Group for Task Timeout Lambda
resource "aws_cloudwatch_log_group" "task_timeout_lambda_log_group" {
  name              = "/aws/lambda/${var.task_timeout_lambda_name}"
  retention_in_days = 14
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
