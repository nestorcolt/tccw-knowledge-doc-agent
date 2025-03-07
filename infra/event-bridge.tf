# EventBridge Rule for Lambda events
resource "aws_cloudwatch_event_rule" "lambda_event_rule" {
  name        = "${var.ecs_task_name}-lambda-event-rule"
  description = "Rule to capture events from Lambda function"

  event_pattern = jsonencode({
    source      = ["tccw.knowledge.doc.agent"]
    detail-type = ["S3ObjectCreated"]
  })
}



# EventBridge Target for ECS Task
resource "aws_cloudwatch_event_target" "ecs_task" {
  rule      = aws_cloudwatch_event_rule.lambda_event_rule.name
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
      assign_public_ip = true # TODO: Change to false when we have a NAT gateway
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
