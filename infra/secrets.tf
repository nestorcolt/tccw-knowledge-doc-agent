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
