# ecs.tf - ECS Cluster, Task Definition, and CloudWatch Log Group

# ---------------------------------------------------------------------------
# ECS Cluster
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = "${var.prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group
# Pre-created so container logs are captured from the very first run.
# Without this, logs are lost if the group doesn't exist when the container starts.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/ecs/${var.prefix}-processor"
  retention_in_days = 30
}

# ---------------------------------------------------------------------------
# ECS Task Definition
#
# image changed from a private ECR URI (which required a Docker build +
# push step before any demo) to the official public Python slim image.
# The container fetches processor.py from S3 at startup via the command
# override below, so no local Docker or ECR push is needed at all.
#
# To restore the private-ECR flow in production:
#   1. Build and push your image to ECR.
#   2. Set container_image in terraform.tfvars to the ECR URI.
#   3. Remove the command block and the S3 cp step.
# ---------------------------------------------------------------------------

resource "aws_ecs_task_definition" "processor" {
  family                   = "${var.prefix}-processor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "processor"

    # use the official public Python image instead of a private ECR URI.
    # This avoids a docker build + push step entirely for the prototype demo.
    image     = "public.ecr.aws/docker/library/python:3.12-slim"

    essential = true

    # at startup the container installs boto3 then pulls processor.py
    # from the scripts/ prefix of the ingress bucket and runs it.
    # The ingress bucket name is resolved at plan time via the Terraform
    # resource reference so no hardcoding is needed.
    command = [
      "bash", "-c",
      "pip install boto3 awscli -q && aws s3 cp s3://${aws_s3_bucket.ingress.bucket}/scripts/processor.py . && python processor.py"
    ]

    # Static environment variables injected at task definition level.
    # S3_BUCKET, S3_KEY, TRACE_ID and ORG_ID are injected at runtime
    # by the Lambda validator via container overrides (see validator.py).
    environment = [
      { name = "AUDIT_TABLE", value = aws_dynamodb_table.audit.name },
      { name = "AWS_REGION",  value = var.aws_region }
    ]

    # CloudWatch logging configuration.
    # Log group is pre-created above to ensure logs are never lost.
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.prefix}-processor"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "processor"
      }
    }

    # Health check not applicable for a batch/exit container,
    # but resource limits are set to prevent runaway tasks.
    ulimits = [{
      name      = "nofile"
      softLimit = 1024
      hardLimit = 2048
    }]
  }])
}
