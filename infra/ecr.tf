
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
