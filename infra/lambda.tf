# Null resource to run the layer packaging script
resource "null_resource" "lambda_layer" {
  triggers = {
    requirements_md5 = filemd5("${path.module}/lambda/requirements.txt")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/build_layer.sh"
  }
}

# Null resource to run the function packaging script
resource "null_resource" "lambda_package" {
  triggers = {
    function_md5 = filemd5("${path.module}/lambda/lambda_function.py")
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/package.sh"
  }
}

# Archive file for Lambda layer
data "archive_file" "lambda_layer_zip" {
  depends_on = [null_resource.lambda_layer]

  type        = "zip"
  source_dir  = "${path.module}/build/layer"
  output_path = "${path.module}/lambda_layer.zip"
}

# Archive file for Lambda function
data "archive_file" "lambda_zip" {
  depends_on = [null_resource.lambda_package]

  type        = "zip"
  source_dir  = "${path.module}/build/package"
  output_path = "${path.module}/lambda_function.zip"
}

# Fetch all secrets from Secrets Manager
data "aws_secretsmanager_secret" "portkey_api_key" {
  name = var.portkey_api_key_secret
}

data "aws_secretsmanager_secret_version" "portkey_api_key" {
  secret_id = data.aws_secretsmanager_secret.portkey_api_key.id
}

data "aws_secretsmanager_secret" "portkey_virtual_key" {
  name = var.portkey_virtual_key_secret
}

data "aws_secretsmanager_secret_version" "portkey_virtual_key" {
  secret_id = data.aws_secretsmanager_secret.portkey_virtual_key.id
}

data "aws_secretsmanager_secret" "long_term_db_password" {
  name = var.long_term_db_password_secret
}

data "aws_secretsmanager_secret_version" "long_term_db_password" {
  secret_id = data.aws_secretsmanager_secret.long_term_db_password.id
}

data "aws_secretsmanager_secret" "chroma_password" {
  name = var.chroma_password_secret
}

data "aws_secretsmanager_secret_version" "chroma_password" {
  secret_id = data.aws_secretsmanager_secret.chroma_password.id
}

data "aws_secretsmanager_secret" "anthropic_api_key" {
  name = var.anthropic_api_key_secret
}

data "aws_secretsmanager_secret_version" "anthropic_api_key" {
  secret_id = data.aws_secretsmanager_secret.anthropic_api_key.id
}

data "aws_secretsmanager_secret" "openai_api_key" {
  name = var.openai_api_key_secret
}

data "aws_secretsmanager_secret_version" "openai_api_key" {
  secret_id = data.aws_secretsmanager_secret.openai_api_key.id
}

data "aws_secretsmanager_secret" "huggingface_api_token" {
  name = var.huggingface_api_token_secret
}

data "aws_secretsmanager_secret_version" "huggingface_api_token" {
  secret_id = data.aws_secretsmanager_secret.huggingface_api_token.id
}

data "aws_secretsmanager_secret" "dockerhub_username" {
  name = var.dockerhub_username_secret
}

data "aws_secretsmanager_secret_version" "dockerhub_username" {
  secret_id = data.aws_secretsmanager_secret.dockerhub_username.id
}

data "aws_secretsmanager_secret" "dockerhub_token" {
  name = var.dockerhub_token_secret
}

data "aws_secretsmanager_secret_version" "dockerhub_token" {
  secret_id = data.aws_secretsmanager_secret.dockerhub_token.id
}

# IAM role for Lambda function
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

# IAM policy for Lambda to access S3, CloudWatch Logs, and Secrets Manager
resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.lambda_function_name}-policy"
  description = "IAM policy for Lambda function ${var.lambda_function_name}"

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
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Create S3 bucket for Lambda code if it doesn't exist
resource "aws_s3_bucket" "lambda_code_bucket" {
  bucket = var.lambda_code_bucket
}

# Upload Lambda layer to S3
resource "aws_s3_object" "lambda_layer" {
  bucket = aws_s3_bucket.lambda_code_bucket.id
  key    = "${var.lambda_function_name}-layer/${filemd5("${path.module}/lambda_layer.zip")}.zip"
  source = "${path.module}/lambda_layer.zip"
  etag   = filemd5("${path.module}/lambda_layer.zip")
}

# Upload Lambda package to S3
resource "aws_s3_object" "lambda_package" {
  bucket = aws_s3_bucket.lambda_code_bucket.id
  key    = "${var.lambda_function_name}/${filemd5("${path.module}/lambda_function.zip")}.zip"
  source = "${path.module}/lambda_function.zip"
  etag   = filemd5("${path.module}/lambda_function.zip")
}

# Create Lambda layer
resource "aws_lambda_layer_version" "dependencies" {
  layer_name = "${var.lambda_function_name}-dependencies"

  s3_bucket = aws_s3_bucket.lambda_code_bucket.id
  s3_key    = aws_s3_object.lambda_layer.key

  compatible_runtimes = [var.lambda_runtime]

  depends_on = [aws_s3_object.lambda_layer]
}

# Lambda function using S3 for code and the layer for dependencies
resource "aws_lambda_function" "tccw_knowledge_doc_agent" {
  function_name = var.lambda_function_name
  description   = var.lambda_description
  role          = aws_iam_role.lambda_role.arn
  handler       = var.lambda_handler
  runtime       = var.lambda_runtime
  timeout       = var.lambda_timeout
  memory_size   = var.lambda_memory_size

  # Use S3 for code
  s3_bucket        = aws_s3_bucket.lambda_code_bucket.id
  s3_key           = aws_s3_object.lambda_package.key
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Use the layer for dependencies
  layers = [aws_lambda_layer_version.dependencies.arn]

  # Add ephemeral storage configuration
  ephemeral_storage {
    size = var.lambda_ephemeral_storage
  }

  environment {
    variables = {
      # Required variables from Secrets Manager
      PORTKEY_API_KEY     = data.aws_secretsmanager_secret_version.portkey_api_key.secret_string,
      PORTKEY_VIRTUAL_KEY = data.aws_secretsmanager_secret_version.portkey_virtual_key.secret_string,

      # Optional variables from Secrets Manager
      LONG_TERM_DB_PASSWORD = data.aws_secretsmanager_secret_version.long_term_db_password.secret_string,
      CHROMA_PASSWORD       = data.aws_secretsmanager_secret_version.chroma_password.secret_string,

      # API Keys
      ANTHROPIC_API_KEY     = data.aws_secretsmanager_secret_version.anthropic_api_key.secret_string,
      OPENAI_API_KEY        = data.aws_secretsmanager_secret_version.openai_api_key.secret_string,
      HUGGINGFACE_API_TOKEN = data.aws_secretsmanager_secret_version.huggingface_api_token.secret_string,

      # Docker credentials
      DOCKERHUB_USERNAME = data.aws_secretsmanager_secret_version.dockerhub_username.secret_string,
      DOCKERHUB_TOKEN    = data.aws_secretsmanager_secret_version.dockerhub_token.secret_string,

      # Optional variables from Terraform variables
      COGNITION_CONFIG_DIR  = var.cognition_config_dir,
      CONFIG_RELOAD_TIMEOUT = var.config_reload_timeout,
      APP_LOG_LEVEL         = var.app_log_level,

      # S3 bucket configuration
      SOURCE_BUCKET_NAME   = var.source_bucket_name,
      SOURCE_BUCKET_PREFIX = var.source_bucket_prefix,
      IGNORED_PREFIXES     = join(",", var.ignored_prefixes)
    }
  }

  depends_on = [
    aws_s3_object.lambda_package,
    aws_lambda_layer_version.dependencies,
    aws_iam_role_policy_attachment.lambda_policy_attachment
  ]
}

# S3 bucket event notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = var.source_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.tccw_knowledge_doc_agent.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = var.source_bucket_prefix
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tccw_knowledge_doc_agent.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.source_bucket_name}"
}
