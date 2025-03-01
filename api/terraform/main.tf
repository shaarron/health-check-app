
variable "image" {
  type = string
}

variable "aws-region" {
  type = string
}

data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_vpc.id]
  }
}
provider "aws" {
  region = var.aws-region
}

terraform {
  backend "s3" {}
}
# ecs cluster
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "api-health-check"
}
# security group for load balancer
resource "aws_security_group" "lb_sg" {
  name        = "api-health-check-lb-sg"
  description = "Allow inbound HTTP and HTTPS traffic"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# security group for ecs
resource "aws_security_group" "ecs_sg" {
  name        = "api-health-check-ecs-sg"
  description = "Allow inbound traffic from ALB"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# task execution role
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ApiHealthCheckTaskExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
# cloudwatch
resource "aws_iam_role_policy_attachment" "ecs_logs_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsWriteAccess"
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/api-health-check-logs"
  retention_in_days = 7
}
# task definition
resource "aws_ecs_task_definition" "api-health-check-task-definition" {
  family                   = "api-health-check"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  network_mode             = "awsvpc"
  memory                   = "512"
  cpu                      = "256"

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "api-health-check"
      image     = var.image
      essential = true
      portMappings = [
        {
          containerPort = 80
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = var.aws-region
          awslogs-stream-prefix = "health-check-ecs"
        }
      }

    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }

}
# load balancer
resource "aws_iam_role" "ecs_service_role" {
  name = "ecs-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_lb" "ecs_lb" {
  name               = "api-health-check-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = data.aws_subnets.default_subnets.ids

  enable_deletion_protection = false
}
# target group
resource "aws_lb_target_group" "ecs_tg" {
  name        = "ecs-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default_vpc.id
  target_type = "ip"

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
# listener
resource "aws_lb_listener" "ecs_listener" {
  load_balancer_arn = aws_lb.ecs_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

data "aws_ecs_task_definition" "existing" {
  task_definition = aws_ecs_task_definition.api-health-check-task-definition.family
}
# ecs service
resource "aws_ecs_service" "service" {
  name            = "api-health-check-service"
  task_definition = data.aws_ecs_task_definition.existing.arn
  cluster         = aws_ecs_cluster.ecs_cluster.id
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default_subnets.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "api-health-check"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}



