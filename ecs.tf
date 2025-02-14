
resource "aws_ecs_cluster" "ecs" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_capacity_provider" "ecs" {
  name = var.cluster_name

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ec2_ecs.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 1000
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "ecs" {
  cluster_name = aws_ecs_cluster.ecs.name

  capacity_providers = [aws_ecs_capacity_provider.ecs.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.ecs.name
  }
}

data "aws_iam_policy_document" "ecs_task_execution" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.cluster_name}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_execution_agent_key_sm" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.warpstream_agent_key_secret_manager_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_agent_key_sm" {
  name = "${var.cluster_name}-ecs-task-execution-agent-key-sm"
  role = aws_iam_role.ecs_task_execution.id

  policy = data.aws_iam_policy_document.ecs_task_execution_agent_key_sm.json
}

data "aws_iam_policy_document" "ecs_task" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"

      values = ["arn:aws:ecs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"

      values = ["${data.aws_caller_identity.current.account_id}"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  name               = "${var.cluster_name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task.json
}

data "aws_iam_policy_document" "ec2_ecs_task_s3_bucket" {
  statement {
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.bucket.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.bucket.bucket}/*"
    ]
  }
}

resource "aws_iam_role_policy" "ec2_ecs_task_s3_bucket" {
  name = "${var.cluster_name}-ecs-task-s3"
  role = aws_iam_role.ecs_task.id

  policy = data.aws_iam_policy_document.ec2_ecs_task_s3_bucket.json
}

locals {
  ecs_cores  = (data.aws_ec2_instance_type.ec2.default_vcpus - 1)
  ecs_cpu    = local.ecs_cores * 1024
  ecs_memory = (data.aws_ec2_instance_type.ec2.memory_size - 4096)
}

resource "aws_ecs_task_definition" "service" {
  family = var.cluster_name

  network_mode = "awsvpc"

  cpu    = local.ecs_cpu
  memory = local.ecs_memory

  task_role_arn      = aws_iam_role.ecs_task.arn
  execution_role_arn = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name : "warpstream-agent",
      image : "public.ecr.aws/warpstream-labs/warpstream_agent:${var.warpstream_agent_version}",
      logConfiguration : {
        logDriver : "awslogs",
        options : {
          awslogs-create-group : "true",
          awslogs-group : "warpstream-agent",
          awslogs-region : data.aws_region.current.name,
          awslogs-stream-prefix : "warpstream-agent"
        }
      },
      cpu : local.ecs_cpu,
      memory : local.ecs_memory,
      portMappings : [
        {
          containerPort : 8080,
          hostPort : 8080,
          protocol : "tcp"
        },
        {
          containerPort : 9092,
          hostPort : 9092,
          protocol : "tcp"
        }
      ],
      essential : true,
      command : [
        "agent"
      ],
      environment : [
        {
          name : "AWS_REGION",
          value : data.aws_region.current.name
        },
        {
          name : "GOMAXPROCS",
          value : tostring(local.ecs_cores)
        },
        {
          name : "WARPSTREAM_BUCKET_URL",
          value : "s3://${aws_s3_bucket.bucket.bucket}"
        },
        {
          name : "WARPSTREAM_DEFAULT_VIRTUAL_CLUSTER_ID",
          value : var.warpstream_virtual_cluster_id
        },
        {
          name : "WARPSTREAM_REGION",
          value : var.control_plane_region
        },
      ],
      secrets : [{
        name : "WARPSTREAM_AGENT_KEY",
        valueFrom : var.warpstream_agent_key_secret_manager_arn
      }],
      healthCheck : {
        command : [
          "CMD-SHELL",
          "/usr/bin/nc -zv 127.0.0.1 8080"
        ],
        interval : 5,
        timeout : 5,
        retries : 3,
        startPeriod : 30
      },
    }
  ])
}

resource "aws_security_group" "ecs_service" {
  name        = "${var.cluster_name}-agents"
  description = "Allow Warpstream Agent Communication"
  vpc_id      = var.ecs_service_vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "allow_agent_to_agent_http" {
  security_group_id = aws_security_group.ecs_service.id
  description       = "Allow Agent to Agent HTTP Communication"

  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.ecs_service.id
}

resource "aws_vpc_security_group_ingress_rule" "allow_agent_to_agent_kafka" {
  security_group_id = aws_security_group.ecs_service.id
  description       = "Allow Agent to Agent Kafka Communication"

  ip_protocol                  = "tcp"
  from_port                    = 9092
  to_port                      = 9092
  referenced_security_group_id = aws_security_group.ecs_service.id
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  count             = var.disable_default_warpstream_agent_egress ? 0 : 1
  security_group_id = aws_security_group.ecs_service.id
  description       = "Allow Agent to Egress"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}


resource "aws_ecs_service" "service" {
  name            = var.cluster_name
  cluster         = aws_ecs_cluster.ecs.id
  task_definition = aws_ecs_task_definition.service.arn

  desired_count                      = length(var.ecs_subnet_ids) # Minimum of one service container per zone
  deployment_minimum_healthy_percent = "100"
  deployment_maximum_percent         = "200"

  lifecycle {
    ignore_changes = [desired_count]
  }

  capacity_provider_strategy {
    base              = 1
    capacity_provider = aws_ecs_capacity_provider.ecs.name
    weight            = 100
  }

  deployment_circuit_breaker {
    enable   = false
    rollback = false
  }

  deployment_controller {
    type = "ECS"
  }

  network_configuration {
    subnets          = var.ecs_subnet_ids
    security_groups  = concat([aws_security_group.ecs_service.id], var.ecs_service_additional_security_group_ids)
    assign_public_ip = false
  }

  triggers = {
    "definition_version" : aws_ecs_task_definition.service.revision
  }
}

resource "aws_appautoscaling_target" "dev_to_target" {
  max_capacity       = var.ecs_service_max_capacity
  min_capacity       = length(var.ecs_subnet_ids) # Minimum of one service container per zone
  resource_id        = "service/${aws_ecs_cluster.ecs.name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "dev_to_cpu" {
  name               = var.cluster_name
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.dev_to_target.resource_id
  scalable_dimension = aws_appautoscaling_target.dev_to_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.dev_to_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    scale_out_cooldown = 0
    scale_in_cooldown  = 1800
    target_value       = 60
  }
}
